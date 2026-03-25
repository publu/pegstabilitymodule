// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {BeefyVaultPSM} from 'contracts/BeefyVaultDDW.sol';
import {IERC20} from '../../interfaces/IERC20.sol';

/// @title MockERC20Echidna
/// @notice Minimal ERC20 for Echidna (no Foundry dependencies)
contract MockERC20Echidna {
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
    require(balanceOf[msg.sender] >= amount, 'insufficient');
    balanceOf[msg.sender] -= amount;
    balanceOf[to] += amount;
    return true;
  }

  function transferFrom(
    address from,
    address to,
    uint256 amount
  ) external returns (bool) {
    require(balanceOf[from] >= amount, 'insufficient');
    require(allowance[from][msg.sender] >= amount, 'allowance');
    allowance[from][msg.sender] -= amount;
    balanceOf[from] -= amount;
    balanceOf[to] += amount;
    return true;
  }
}

/// @title MockBeefyVault
/// @notice Minimal IBeefy vault with 1:1 share ratio for deterministic testing
contract MockBeefyVault {
  MockERC20Echidna public underlying;
  uint8 public decimals = 18;
  uint256 public totalSupply;
  mapping(address => uint256) public balanceOf;

  constructor(
    MockERC20Echidna _underlying
  ) {
    underlying = _underlying;
  }

  function want() external view returns (address) {
    return address(underlying);
  }

  function balance() external view returns (uint256) {
    return totalSupply;
  }

  function deposit(
    uint256 amount
  ) external {
    underlying.transferFrom(msg.sender, address(this), amount);
    balanceOf[msg.sender] += amount;
    totalSupply += amount;
  }

  function depositAll() external {
    uint256 amount = underlying.balanceOf(msg.sender);
    if (amount == 0) return;
    underlying.transferFrom(msg.sender, address(this), amount);
    balanceOf[msg.sender] += amount;
    totalSupply += amount;
  }

  function withdraw(
    uint256 shares
  ) external {
    require(balanceOf[msg.sender] >= shares, 'insufficient shares');
    balanceOf[msg.sender] -= shares;
    totalSupply -= shares;
    underlying.transfer(msg.sender, shares);
  }

  function withdrawAll() external {
    uint256 shares = balanceOf[msg.sender];
    if (shares == 0) return;
    balanceOf[msg.sender] = 0;
    totalSupply -= shares;
    underlying.transfer(msg.sender, shares);
  }

  function getPricePerFullShare() external pure returns (uint256) {
    return 1e18;
  }
}

/// @title EchidnaBeefyPSM
/// @notice Echidna property test harness for BeefyVaultPSM (Base version)
/// @dev Uses hevm.etch to deploy mock MAI at the hardcoded MAI_ADDRESS,
///      hevm.warp to advance time for withdrawal epochs,
///      and hevm.prank to impersonate fuzz senders for multi-actor testing.
contract EchidnaBeefyPSM {
  // HEVM cheatcode interface (Echidna 2.x)
  address internal constant HEVM = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
  // Hardcoded MAI address in BeefyVaultPSM (Base)
  address internal constant MAI_BASE = 0xbf1aeA8670D2528E08334083616dD9C5F3B087aE;

  BeefyVaultPSM internal psm;
  MockERC20Echidna internal usdc;
  MockERC20Echidna internal mai;
  MockBeefyVault internal vault;

  // Privileged actors must be part of echidna.yaml's sender set so owner-only
  // and guardian-only paths remain reachable during fuzzing.
  address internal constant OWNER = address(0x20000);
  address internal constant GUARDIAN = address(0x30000);

  // Ghost variables for bookkeeping (public for post-run inspection)
  uint256 public ghost_totalDeposited;
  uint256 public ghost_totalScheduledMAI;
  uint256 public ghost_totalWithdrawnMAI;
  uint256 public ghost_totalRefundedMAI;
  uint256 public ghost_totalSwept;
  uint256 public ghost_depositCount;
  uint256 public ghost_scheduleCount;
  uint256 public ghost_withdrawCount;
  uint256 public ghost_evacuateCount;
  uint256 public ghost_refundCount;

  constructor() {
    usdc = new MockERC20Echidna('USDC', 'USDC', 6);

    // Deploy mock MAI at a temp address to get runtime bytecode
    MockERC20Echidna tempMai = new MockERC20Echidna('MAI', 'MAI', 18);

    // Etch the mock's runtime code at the hardcoded MAI address
    bytes memory maiCode = address(tempMai).code;
    require(maiCode.length > 0, 'etch: empty code');
    (bool etchOk,) = HEVM.call(abi.encodeWithSignature('etch(address,bytes)', MAI_BASE, maiCode));
    require(etchOk, 'etch failed');

    // Now the mock MAI is live at MAI_BASE
    mai = MockERC20Echidna(MAI_BASE);

    // Deploy mock Beefy vault and PSM
    vault = new MockBeefyVault(usdc);
    psm = new BeefyVaultPSM();
    psm.initialize(address(vault), 0, 30); // 0% deposit, 30bps withdrawal
    psm.setGuardian(GUARDIAN, true);
    psm.transferOwnership(OWNER);
    require(psm.guardians(GUARDIAN), 'guardian handoff failed');
    require(psm.owner() == OWNER, 'owner handoff failed');

    // Fund PSM with MAI for deposits (mint on the etched mock)
    mai.mint(address(psm), 100_000_000 * 10 ** 18);
  }

  // ═══════════════════════════════════════════════════════════
  //  HEVM helpers
  // ═══════════════════════════════════════════════════════════

  function _prank(
    address actor
  ) internal {
    (bool ok,) = HEVM.call(abi.encodeWithSignature('prank(address)', actor));
    require(ok, 'prank failed');
  }

  function _warp(
    uint256 timestamp
  ) internal {
    (bool ok,) = HEVM.call(abi.encodeWithSignature('warp(uint256)', timestamp));
    require(ok, 'warp failed');
  }

  // ═══════════════════════════════════════════════════════════
  //  Actions (called by Echidna fuzzer)
  //  msg.sender = fuzz sender (e.g., 0x20000, 0x30000, 0x40000)
  //  hevm.prank ensures PSM sees the fuzz sender, not the harness
  // ═══════════════════════════════════════════════════════════

  function deposit(
    uint256 amount
  ) public {
    if (psm.evacuated()) return;
    amount = _clamp(amount, 2 * 10 ** 6, 100_000 * 10 ** 6);

    address actor = msg.sender;

    // Mint USDC to actor and have actor approve PSM
    usdc.mint(actor, amount);
    _prank(actor);
    usdc.approve(address(psm), amount);

    // Actor deposits into PSM
    _prank(actor);
    try psm.deposit(amount) {
      ghost_totalDeposited += amount;
      ghost_depositCount++;
    } catch {}
  }

  function scheduleWithdraw(
    uint256 amount
  ) public {
    if (psm.evacuated()) return;

    address actor = msg.sender;
    if (psm.withdrawalEpoch(actor) != 0) return;

    uint256 totalStable = psm.totalStableLiquidity();
    uint256 totalQueued = psm.totalQueuedLiquidity();
    if (totalStable <= totalQueued) return;

    uint256 availableUsdc = totalStable - totalQueued;
    uint256 availableMai = availableUsdc * 10 ** 12;
    if (availableMai < 2 * 10 ** 18) return;

    amount = _clamp(amount, 2 * 10 ** 18, availableMai);

    // Mint MAI to actor and have actor approve PSM
    mai.mint(actor, amount);
    _prank(actor);
    mai.approve(address(psm), amount);

    // Actor schedules withdrawal
    _prank(actor);
    try psm.scheduleWithdraw(amount) {
      ghost_totalScheduledMAI += amount;
      ghost_scheduleCount++;
    } catch {}
  }

  function withdraw() public {
    address actor = msg.sender;
    if (psm.withdrawalEpoch(actor) == 0) return;
    if (psm.evacuated()) return; // withdraw blocked post-evacuation

    // Warp past the 3-day withdrawal delay
    uint256 epoch = psm.withdrawalEpoch(actor);
    if (block.timestamp < epoch) {
      _warp(epoch);
    }

    uint256 scheduled = psm.scheduledWithdrawalAmount(actor);

    _prank(actor);
    try psm.withdraw() {
      ghost_totalWithdrawnMAI += scheduled;
      ghost_withdrawCount++;
    } catch {}
  }

  function evacuateVault() public {
    address actor = msg.sender;
    if (actor != GUARDIAN && actor != OWNER) return;
    if (psm.evacuated()) return;

    _prank(actor);
    try psm.evacuateVault() {
      ghost_evacuateCount++;
    } catch {}
  }

  function claimRefund() public {
    if (!psm.evacuated()) return;

    address actor = msg.sender;
    if (psm.scheduledWithdrawalAmount(actor) == 0) return;

    uint256 scheduled = psm.scheduledWithdrawalAmount(actor);

    _prank(actor);
    try psm.claimRefund() {
      ghost_totalRefundedMAI += scheduled;
      ghost_refundCount++;
    } catch {}
  }

  function forceSettle(
    address target
  ) public {
    if (msg.sender != OWNER) return;
    if (!psm.evacuated()) return;
    if (block.timestamp < psm.evacuationTime() + psm.SETTLEMENT_TIMEOUT()) return;
    if (psm.scheduledWithdrawalAmount(target) == 0) return;

    uint256 scheduled = psm.scheduledWithdrawalAmount(target);

    _prank(OWNER);
    try psm.forceSettle(target) {
      ghost_totalRefundedMAI += scheduled;
      ghost_refundCount++;
    } catch {}
  }

  function sweep(
    uint256 amount
  ) public {
    if (psm.evacuated()) return;
    if (msg.sender != OWNER) return;

    amount = _clamp(amount, 1 * 10 ** 6, 50_000 * 10 ** 6);
    usdc.mint(address(psm), amount);

    _prank(OWNER);
    try psm.sweep() {
      ghost_totalSwept += amount;
    } catch {}
  }

  function ownerWithdrawMAI() public {
    if (msg.sender != OWNER) return;
    _prank(OWNER);
    try psm.withdrawMAI() {} catch {}
  }

  function ownerTransferMAI(
    uint256 amount
  ) public {
    if (msg.sender != OWNER) return;

    uint256 maiBalance = mai.balanceOf(address(psm));
    if (maiBalance == 0) return;
    amount = _clamp(amount, 1, maiBalance);

    _prank(OWNER);
    try psm.transferToken(address(mai), OWNER, amount) {} catch {}
  }

  // ═══════════════════════════════════════════════════════════
  //  Properties (Echidna property mode)
  // ═══════════════════════════════════════════════════════════

  /// @notice PROPERTY 1: totalQueuedLiquidity <= totalStableLiquidity
  function echidna_queued_never_exceeds_stable() public view returns (bool) {
    return psm.totalStableLiquidity() >= psm.totalQueuedLiquidity();
  }

  /// @notice PROPERTY 2: vault backing + idle USDC >= totalStableLiquidity
  function echidna_backing_sufficient() public view returns (bool) {
    uint256 vaultBacking = vault.balanceOf(address(psm));
    uint256 idleUsdc = usdc.balanceOf(address(psm));
    return (vaultBacking + idleUsdc) >= psm.totalStableLiquidity();
  }

  /// @notice PROPERTY 3: post-evacuation, MAI balance >= totalQueuedMAI
  function echidna_evacuated_mai_covers_refunds() public view returns (bool) {
    if (!psm.evacuated()) return true;
    if (psm.totalQueuedMAI() == 0) return true;
    return mai.balanceOf(address(psm)) >= psm.totalQueuedMAI();
  }

  /// @notice PROPERTY 4: evacuation implies stopped
  function echidna_evacuation_implies_stopped() public view returns (bool) {
    if (psm.evacuated()) {
      return psm.stopped();
    }
    return true;
  }

  /// @notice PROPERTY 5: totalQueuedMAI bounded (no underflow)
  function echidna_totalQueuedMAI_bounded() public view returns (bool) {
    return psm.totalQueuedMAI() <= 100_000_000 * 10 ** 18;
  }

  // ═══════════════════════════════════════════════════════════
  //  Helpers
  // ═══════════════════════════════════════════════════════════

  function _clamp(
    uint256 value,
    uint256 low,
    uint256 high
  ) internal pure returns (uint256) {
    if (value < low) return low;
    if (value > high) return high;
    return value;
  }
}
