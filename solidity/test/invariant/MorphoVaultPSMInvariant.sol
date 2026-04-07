// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from 'forge-std/Test.sol';
import {StdInvariant} from 'forge-std/StdInvariant.sol';
import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {MorphoVaultPSM} from 'contracts/MorphoVaultPSM.sol';
import {IFly} from '../../interfaces/IFly.sol';
import {console} from 'forge-std/console.sol';

/// @title MockERC20
/// @notice Minimal ERC20 for invariant testing without fork
contract MockERC20 {
  string public name;
  string public symbol;
  uint8 public decimals;
  uint256 public totalSupply;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  constructor(
    string memory _name,
    string memory _symbol,
    uint8 _decimals
  ) {
    name = _name;
    symbol = _symbol;
    decimals = _decimals;
  }

  function mint(
    address to,
    uint256 amount
  ) external {
    balanceOf[to] += amount;
    totalSupply += amount;
  }

  function approve(
    address spender,
    uint256 amount
  ) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }

  function transfer(
    address to,
    uint256 amount
  ) external returns (bool) {
    require(balanceOf[msg.sender] >= amount, 'ERC20: insufficient balance');
    balanceOf[msg.sender] -= amount;
    balanceOf[to] += amount;
    return true;
  }

  function transferFrom(
    address from,
    address to,
    uint256 amount
  ) external returns (bool) {
    require(balanceOf[from] >= amount, 'ERC20: insufficient balance');
    require(allowance[from][msg.sender] >= amount, 'ERC20: insufficient allowance');
    allowance[from][msg.sender] -= amount;
    balanceOf[from] -= amount;
    balanceOf[to] += amount;
    return true;
  }
}

/// @title MockERC4626
/// @notice Minimal ERC4626 vault with 1:1 share ratio for deterministic testing
contract MockERC4626 {
  MockERC20 public underlying;
  string public name = 'Mock Vault';
  string public symbol = 'mVault';
  uint8 public decimals;

  uint256 public totalSupply;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  constructor(
    MockERC20 _underlying
  ) {
    underlying = _underlying;
    decimals = _underlying.decimals();
  }

  function asset() external view returns (address) {
    return address(underlying);
  }

  function convertToAssets(
    uint256 shares
  ) external pure returns (uint256) {
    return shares; // 1:1 ratio for deterministic invariant testing
  }

  function convertToShares(
    uint256 assets
  ) external pure returns (uint256) {
    return assets;
  }

  function deposit(
    uint256 assets,
    address receiver
  ) external returns (uint256 shares) {
    underlying.transferFrom(msg.sender, address(this), assets);
    shares = assets; // 1:1
    balanceOf[receiver] += shares;
    totalSupply += shares;
    return shares;
  }

  function withdraw(
    uint256 assets,
    address receiver,
    address _owner
  ) external returns (uint256 shares) {
    shares = assets; // 1:1
    require(balanceOf[_owner] >= shares, 'ERC4626: insufficient shares');
    if (msg.sender != _owner) {
      require(allowance[_owner][msg.sender] >= shares, 'ERC4626: insufficient allowance');
      allowance[_owner][msg.sender] -= shares;
    }
    balanceOf[_owner] -= shares;
    totalSupply -= shares;
    underlying.transfer(receiver, assets);
    return shares;
  }

  function redeem(
    uint256 shares,
    address receiver,
    address _owner
  ) external returns (uint256 assets) {
    require(balanceOf[_owner] >= shares, 'ERC4626: insufficient shares');
    if (msg.sender != _owner) {
      require(allowance[_owner][msg.sender] >= shares, 'ERC4626: insufficient allowance');
      allowance[_owner][msg.sender] -= shares;
    }
    assets = shares; // 1:1
    balanceOf[_owner] -= shares;
    totalSupply -= shares;
    underlying.transfer(receiver, assets);
    return assets;
  }

  function approve(
    address spender,
    uint256 amount
  ) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }
}

/// @title MorphoPSMHandler
/// @notice Handler for invariant testing — no fork needed
contract MorphoPSMHandler is Test {
  MorphoVaultPSM public psm;
  MockERC20 public usdc;
  MockERC20 public mai;
  MockERC4626 public vault;

  address public owner;
  address public guardian;
  address public guardian2;
  address[] public actors;

  // Ghost variables
  uint256 public ghost_totalDeposited;
  uint256 public ghost_totalWithdrawnExecuted;
  uint256 public ghost_totalSwept;
  uint256 public ghost_totalRefunded;
  uint256 public ghost_depositCount;
  uint256 public ghost_scheduleCount;
  uint256 public ghost_withdrawCount;
  uint256 public ghost_sweepCount;
  uint256 public ghost_evacuateCount;
  uint256 public ghost_refundCount;

  constructor(
    MorphoVaultPSM _psm,
    MockERC20 _usdc,
    MockERC20 _mai,
    MockERC4626 _vault,
    address _owner,
    address _guardian
  ) {
    psm = _psm;
    usdc = _usdc;
    mai = _mai;
    vault = _vault;
    owner = _owner;
    guardian = _guardian;
    guardian2 = makeAddr('guardian2');

    for (uint256 i = 0; i < 10; i++) {
      actors.push(makeAddr(string(abi.encodePacked('actor', i))));
    }
  }

  function deposit(
    uint256 actorIndex,
    uint256 amount
  ) public {
    if (psm.evacuated()) return;

    address actor = actors[actorIndex % actors.length];
    amount = bound(amount, 1 * 10 ** 6, 100_000 * 10 ** 6);

    usdc.mint(actor, amount);
    vm.startPrank(actor);
    usdc.approve(address(psm), amount);

    try psm.deposit(amount) {
      ghost_totalDeposited += amount;
      ghost_depositCount++;
    } catch {}
    vm.stopPrank();
  }

  function scheduleWithdraw(
    uint256 actorIndex,
    uint256 amount
  ) public {
    if (psm.evacuated()) return;

    address actor = actors[actorIndex % actors.length];
    if (psm.withdrawalEpoch(actor) != 0) return;

    uint256 totalStable = psm.totalStableLiquidity();
    uint256 totalQueued = psm.totalQueuedLiquidity();
    if (totalStable <= totalQueued) return;

    uint256 availableUsdc = totalStable - totalQueued;
    uint256 availableMai = availableUsdc * 10 ** 12;
    if (availableMai < psm.minimumWithdrawalFee()) return;

    amount = bound(amount, psm.minimumWithdrawalFee(), availableMai);

    mai.mint(actor, amount);
    vm.startPrank(actor);
    mai.approve(address(psm), amount);

    try psm.scheduleWithdraw(amount) {
      ghost_scheduleCount++;
    } catch {}
    vm.stopPrank();
  }

  function withdraw(
    uint256 actorIndex
  ) public {
    if (psm.evacuated()) return;

    address actor = actors[actorIndex % actors.length];
    if (psm.withdrawalEpoch(actor) == 0) return;
    if (block.timestamp < psm.withdrawalEpoch(actor)) {
      vm.warp(psm.withdrawalEpoch(actor));
    }

    uint256 scheduled = psm.scheduledWithdrawalAmount(actor);

    vm.startPrank(actor);
    try psm.withdraw() {
      ghost_totalWithdrawnExecuted += scheduled / 10 ** 12;
      ghost_withdrawCount++;
    } catch {}
    vm.stopPrank();
  }

  function evacuateVault(
    uint256 _guardianSeed
  ) public {
    if (psm.evacuated()) return;

    // Alternate between guardians to exercise multi-guardian access
    address caller = _guardianSeed % 2 == 0 ? guardian : guardian2;
    vm.prank(caller);
    try psm.evacuateVault() {
      ghost_evacuateCount++;
      console.log('[handler] evacuateVault');
    } catch {}
  }

  function claimRefund(
    uint256 actorIndex
  ) public {
    if (!psm.evacuated()) return;

    address actor = actors[actorIndex % actors.length];
    if (psm.scheduledWithdrawalAmount(actor) == 0) return;

    uint256 scheduled = psm.scheduledWithdrawalAmount(actor);
    uint256 refundUsdc = scheduled / 10 ** 12;

    vm.prank(actor);
    try psm.claimRefund() {
      ghost_totalRefunded += refundUsdc;
      ghost_refundCount++;
      console.log('[handler] claimRefund', refundUsdc);
    } catch {}
  }

  function sweep(
    uint256 amount
  ) public {
    if (psm.evacuated()) return;

    amount = bound(amount, 1 * 10 ** 6, 50_000 * 10 ** 6);
    usdc.mint(address(psm), amount);

    vm.prank(owner);
    try psm.sweep() {
      ghost_totalSwept += amount;
      ghost_sweepCount++;
    } catch {}
  }

  function ownerWithdrawMAI() public {
    if (!psm.evacuated()) return; // Only interesting post-evacuation

    vm.prank(owner);
    try psm.withdrawMAI() {} catch {}
  }

  function ownerTransferToken(
    uint256 amount
  ) public {
    if (!psm.evacuated()) return;

    // Try to transfer some MAI (tests the reserve protection)
    uint256 maiBalance = mai.balanceOf(address(psm));
    if (maiBalance == 0) return;
    amount = bound(amount, 1, maiBalance);

    vm.prank(owner);
    try psm.transferToken(address(mai), owner, amount) {} catch {}
  }

  function warpTime(
    uint256 secondsToWarp
  ) public {
    secondsToWarp = bound(secondsToWarp, 0, 7 days);
    vm.warp(block.timestamp + secondsToWarp);
  }
}

/// @title MorphoVaultPSMInvariantTest
/// @notice All operations mixed — chaos scenario (no fork, uses mocks)
contract MorphoVaultPSMInvariantTest is StdInvariant, Test {
  MorphoVaultPSM internal psm;
  MorphoPSMHandler internal handler;
  MockERC20 internal usdc;
  MockERC20 internal mai;
  MockERC4626 internal vault;

  address internal owner = makeAddr('owner');
  address internal guardian = makeAddr('guardian');

  function setUp() public {
    // Deploy mocks
    usdc = new MockERC20('USD Coin', 'USDC', 6);
    mai = new MockERC20('MAI', 'MAI', 18);
    vault = new MockERC4626(usdc);

    // Deploy PSM
    vm.startPrank(owner);
    psm = new MorphoVaultPSM();
    vm.stopPrank();

    // Fund PSM with MAI
    mai.mint(address(psm), 10_000_000 * 10 ** 18);

    // Initialize
    vm.startPrank(owner);
    psm.initialize(address(vault), 0, 30, address(mai));
    psm.setGuardian(guardian, true);
    vm.stopPrank();

    // Setup handler
    handler = new MorphoPSMHandler(psm, usdc, mai, vault, owner, guardian);

    // Register handler's second guardian on PSM
    address g2 = handler.guardian2();
    vm.prank(owner);
    psm.setGuardian(g2, true);

    targetContract(address(handler));

    bytes4[] memory selectors = new bytes4[](9);
    selectors[0] = MorphoPSMHandler.deposit.selector;
    selectors[1] = MorphoPSMHandler.scheduleWithdraw.selector;
    selectors[2] = MorphoPSMHandler.withdraw.selector;
    selectors[3] = MorphoPSMHandler.evacuateVault.selector;
    selectors[4] = MorphoPSMHandler.claimRefund.selector;
    selectors[5] = MorphoPSMHandler.sweep.selector;
    selectors[6] = MorphoPSMHandler.warpTime.selector;
    selectors[7] = MorphoPSMHandler.ownerWithdrawMAI.selector;
    selectors[8] = MorphoPSMHandler.ownerTransferToken.selector;

    targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
  }

  /// @notice INVARIANT: totalStableLiquidity >= totalQueuedLiquidity always
  function invariant_queuedNeverExceedsStable() public {
    assertGe(
      psm.totalStableLiquidity(),
      psm.totalQueuedLiquidity(),
      'INVARIANT VIOLATED: totalQueuedLiquidity exceeds totalStableLiquidity'
    );
  }

  /// @notice INVARIANT: vault + idle USDC backing >= totalStableLiquidity
  function invariant_backingSufficient() public {
    uint256 vaultAssets = vault.convertToAssets(vault.balanceOf(address(psm)));
    uint256 idleUsdc = usdc.balanceOf(address(psm));
    uint256 totalBacking = vaultAssets + idleUsdc;

    assertGe(totalBacking, psm.totalStableLiquidity(), 'INVARIANT VIOLATED: backing < totalStableLiquidity');
  }

  /// @notice INVARIANT: when evacuated, MAI balance covers queued refunds
  function invariant_evacuatedMaiCoverage() public {
    if (!psm.evacuated()) return;
    if (psm.totalQueuedLiquidity() == 0) return;

    uint256 maiBalance = mai.balanceOf(address(psm));
    uint256 maiNeeded = psm.totalQueuedMAI();

    assertGe(maiBalance, maiNeeded, 'INVARIANT VIOLATED: insufficient MAI for queued refunds');
  }

  /// @notice Summary stats
  function invariant_callSummary() public view {
    console.log('--- Morpho PSM Invariant Summary ---');
    console.log('deposits:', handler.ghost_depositCount(), '| swept:', handler.ghost_sweepCount());
    console.log('schedules:', handler.ghost_scheduleCount(), '| withdraws:', handler.ghost_withdrawCount());
    console.log('evacuates:', handler.ghost_evacuateCount(), '| refunds:', handler.ghost_refundCount());
    console.log('stable:', psm.totalStableLiquidity(), '| queued:', psm.totalQueuedLiquidity());
    console.log('evacuated:', psm.evacuated() ? 1 : 0);
  }
}

/// @title MorphoVaultPSMInvariantNormalOps
/// @notice Normal operations + sweep only (no evacuation) — regression baseline
contract MorphoVaultPSMInvariantNormalOps is StdInvariant, Test {
  MorphoVaultPSM internal psm;
  MorphoPSMHandler internal handler;
  MockERC20 internal usdc;
  MockERC20 internal mai;
  MockERC4626 internal vault;

  address internal owner = makeAddr('owner');
  address internal guardian = makeAddr('guardian');

  function setUp() public {
    usdc = new MockERC20('USD Coin', 'USDC', 6);
    mai = new MockERC20('MAI', 'MAI', 18);
    vault = new MockERC4626(usdc);

    vm.startPrank(owner);
    psm = new MorphoVaultPSM();
    vm.stopPrank();

    mai.mint(address(psm), 10_000_000 * 10 ** 18);

    vm.startPrank(owner);
    psm.initialize(address(vault), 0, 30, address(mai));
    psm.setGuardian(guardian, true);
    vm.stopPrank();

    handler = new MorphoPSMHandler(psm, usdc, mai, vault, owner, guardian);

    // Register handler's second guardian on PSM
    address g2 = handler.guardian2();
    vm.prank(owner);
    psm.setGuardian(g2, true);

    targetContract(address(handler));

    bytes4[] memory selectors = new bytes4[](5);
    selectors[0] = MorphoPSMHandler.deposit.selector;
    selectors[1] = MorphoPSMHandler.scheduleWithdraw.selector;
    selectors[2] = MorphoPSMHandler.withdraw.selector;
    selectors[3] = MorphoPSMHandler.sweep.selector;
    selectors[4] = MorphoPSMHandler.warpTime.selector;

    targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
  }

  function invariant_queuedNeverExceedsStable() public {
    assertGe(psm.totalStableLiquidity(), psm.totalQueuedLiquidity(), 'queued exceeds stable');
  }

  function invariant_backingSufficient() public {
    uint256 vaultAssets = vault.convertToAssets(vault.balanceOf(address(psm)));
    uint256 idleUsdc = usdc.balanceOf(address(psm));

    assertGe(vaultAssets + idleUsdc, psm.totalStableLiquidity(), 'backing < stable');
  }
}
