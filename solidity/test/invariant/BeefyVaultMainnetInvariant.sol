// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from 'forge-std/Test.sol';
import {StdInvariant} from 'forge-std/StdInvariant.sol';
import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {BeefyVaultPSMV2} from 'contracts/BeefyVaultPSM/V2.sol';
import {IBeefy} from '../../interfaces/IBeefy.sol';
import {console} from 'forge-std/console.sol';

/// @title PSMHandler
/// @notice Handler contract for invariant testing - exposes bounded actions
contract PSMHandler is Test {
  BeefyVaultPSMV2 public psm;
  IERC20 public usdcToken;
  IERC20 public maiToken;

  address[] public actors;
  address internal currentActor;

  // Ghost variables for tracking
  uint256 public ghost_totalDeposited;
  uint256 public ghost_totalWithdrawnScheduled;
  uint256 public ghost_totalWithdrawnExecuted;
  uint256 public ghost_depositCount;
  uint256 public ghost_scheduleCount;
  uint256 public ghost_withdrawCount;

  // MAI whale address (owner with large balance)
  address internal constant MAI_WHALE = 0x3182E6856c3B59C39114416075770Ec9DC9Ff436;

  constructor(BeefyVaultPSMV2 _psm, IERC20 _usdc, IERC20 _mai) {
    psm = _psm;
    usdcToken = _usdc;
    maiToken = _mai;

    // Create actor pool
    for (uint256 i = 0; i < 10; i++) {
      actors.push(makeAddr(string(abi.encodePacked('actor', i))));
    }
  }

  /// @notice Helper to deal tokens by writing directly to storage or transferring from whale
  /// @dev USDC uses slot 9 for balances, MAI uses whale transfer due to non-standard storage
  /// @dev For MAI, this stops current prank and uses whale - caller must handle prank state
  function _dealToken(address token, address to, uint256 amount) internal {
    if (token == address(maiToken)) {
      // MAI has non-standard storage layout, transfer from whale instead
      vm.stopPrank();
      vm.prank(MAI_WHALE);
      IERC20(token).transfer(to, amount);
    } else {
      // USDC uses slot 9 for balances (vm.store doesn't need prank context)
      uint256 slot;
      if (token == address(usdcToken)) {
        slot = 9; // USDC balance slot
      } else {
        slot = 0; // Standard ERC20 balance slot
      }
      bytes32 storageSlot = keccak256(abi.encode(to, slot));
      vm.store(token, storageSlot, bytes32(amount));
    }
  }

  /// @notice Deposit USDC into the PSM
  function deposit(uint256 actorIndex, uint256 amount) public {
    currentActor = actors[actorIndex % actors.length];
    amount = bound(amount, psm.minimumDepositFee() + 1, 100_000 * 10 ** 6);

    _dealToken(address(usdcToken), currentActor, amount);
    vm.startPrank(currentActor);
    usdcToken.approve(address(psm), amount);

    try psm.deposit(amount) {
      ghost_totalDeposited += amount;
      ghost_depositCount++;
    } catch {}
    vm.stopPrank();
  }

  /// @notice Schedule a withdrawal from the PSM
  function scheduleWithdraw(uint256 actorIndex, uint256 amount) public {
    currentActor = actors[actorIndex % actors.length];

    // Skip if user already has a pending withdrawal
    if (psm.withdrawalEpoch(currentActor) != 0) return;

    uint256 available = psm.availableForWithdrawalInMAI();
    if (available == 0) return;

    // Bound to minimum fee and available amount
    uint256 minWithdraw = psm.minimumWithdrawalFee();
    if (available < minWithdraw) return;

    amount = bound(amount, minWithdraw, available);

    // _dealToken for MAI stops any active prank
    _dealToken(address(maiToken), currentActor, amount);
    vm.startPrank(currentActor);
    maiToken.approve(address(psm), amount);

    try psm.scheduleWithdraw(amount) {
      ghost_totalWithdrawnScheduled += amount / 10 ** 12;
      ghost_scheduleCount++;
    } catch {}
    vm.stopPrank();
  }

  /// @notice Execute a pending withdrawal
  function withdraw(uint256 actorIndex) public {
    currentActor = actors[actorIndex % actors.length];

    if (psm.withdrawalEpoch(currentActor) == 0) return;
    if (block.timestamp < psm.withdrawalEpoch(currentActor)) {
      vm.warp(psm.withdrawalEpoch(currentActor));
    }

    uint256 scheduled = psm.scheduledWithdrawalAmount(currentActor);

    vm.startPrank(currentActor);
    try psm.withdraw() {
      ghost_totalWithdrawnExecuted += scheduled / 10 ** 12;
      ghost_withdrawCount++;
    } catch {}
    vm.stopPrank();
  }

  /// @notice Warp time forward
  function warpTime(uint256 secondsToWarp) public {
    secondsToWarp = bound(secondsToWarp, 0, 7 days);
    vm.warp(block.timestamp + secondsToWarp);
  }

  /// @notice Get count of actors
  function getActorCount() external view returns (uint256) {
    return actors.length;
  }
}

/// @title BeefyVaultMainnetInvariantTest
/// @notice Invariant tests for the mainnet PSM with minimum reserves
contract BeefyVaultMainnetInvariantTest is StdInvariant, Test {
  // Use latest block for public RPCs
  // uint256 internal constant _FORK_BLOCK = 21_350_000;

  BeefyVaultPSMV2 internal psm;
  PSMHandler internal handler;

  IERC20 internal usdcToken = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
  IERC20 internal maiToken = IERC20(0x8D6CeBD76f18E1558D4DB88138e2DeFB3909fAD6);
  IERC20 internal mooToken = IERC20(0x562Ea6FfFD1293b9433E7b81A2682C31892ea013);

  // MAI whale address (owner with large balance)
  address internal constant MAI_WHALE = 0x3182E6856c3B59C39114416075770Ec9DC9Ff436;

  /// @notice Helper to deal tokens by writing directly to storage or transferring from whale
  /// @dev USDC uses slot 9 for balances, MAI uses whale transfer due to non-standard storage
  function _dealToken(address token, address to, uint256 amount) internal {
    if (token == address(maiToken)) {
      // MAI has non-standard storage layout, transfer from whale instead
      vm.prank(MAI_WHALE);
      IERC20(token).transfer(to, amount);
    } else {
      // USDC uses slot 9 for balances
      uint256 slot;
      if (token == address(usdcToken)) {
        slot = 9; // USDC balance slot
      } else {
        slot = 0; // Standard ERC20 balance slot
      }
      bytes32 storageSlot = keccak256(abi.encode(to, slot));
      vm.store(token, storageSlot, bytes32(amount));
    }
  }

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl('mainnet'));

    address owner = makeAddr('owner');
    vm.startPrank(owner);

    psm = new BeefyVaultPSMV2();
    vm.stopPrank();
    // Note: Whale has ~7M MAI, so we use 5M to leave buffer for actors
    _dealToken(address(maiToken), address(psm), 5_000_000 * 10 ** 18);
    vm.startPrank(owner);
    psm.initialize(address(mooToken), 100, 100, address(maiToken));

    // Set a meaningful minimum reserves for testing
    psm.setMinimumReserves(1000 * 10 ** 6); // 1000 USDC

    vm.stopPrank();

    handler = new PSMHandler(psm, usdcToken, maiToken);

    targetContract(address(handler));

    bytes4[] memory selectors = new bytes4[](4);
    selectors[0] = PSMHandler.deposit.selector;
    selectors[1] = PSMHandler.scheduleWithdraw.selector;
    selectors[2] = PSMHandler.withdraw.selector;
    selectors[3] = PSMHandler.warpTime.selector;

    targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
  }

  /// @notice INVARIANT: Available liquidity must never go below minimum reserves after scheduling
  /// @dev This checks that scheduleWithdraw properly enforces the minimum reserves constraint
  function invariant_minimumReservesRespected() public {
    uint256 totalStable = psm.totalStableLiquidity();
    uint256 totalQueued = psm.totalQueuedLiquidity();
    uint256 minReserves = psm.minimumReserves();

    // Available liquidity after all queued withdrawals
    uint256 availableLiquidity = totalStable - totalQueued;

    // Either there's enough liquidity to cover minimum reserves,
    // OR total liquidity is less than minimum (edge case when min reserves set after deposits)
    bool reservesRespected = availableLiquidity >= minReserves || totalStable < minReserves;

    assertTrue(reservesRespected, 'INVARIANT VIOLATED: Minimum reserves breached');
  }

  /// @notice INVARIANT: Total queued liquidity cannot exceed total stable liquidity
  function invariant_queuedNeverExceedsTotal() public {
    assertLe(psm.totalQueuedLiquidity(), psm.totalStableLiquidity(), 'INVARIANT VIOLATED: Queued exceeds total');
  }

  /// @notice INVARIANT: availableForWithdrawal() matches the contract's reserve and fee-floor logic
  function invariant_availableForWithdrawalCorrect() public {
    uint256 available = psm.availableForWithdrawal();
    uint256 totalStable = psm.totalStableLiquidity();
    uint256 totalQueued = psm.totalQueuedLiquidity();
    uint256 minReserves = psm.minimumReserves();

    uint256 availableLiquidity = totalStable - totalQueued;
    uint256 expectedAvailable;

    if (availableLiquidity > minReserves) {
      uint256 netAvailable = availableLiquidity - minReserves;
      if (netAvailable > psm.calculateFee(netAvailable, false)) {
        expectedAvailable = netAvailable;
      }
    }

    assertEq(available, expectedAvailable, 'INVARIANT VIOLATED: Available calculation incorrect');
  }

  /// @notice INVARIANT: availableForWithdrawalInMAI is correctly scaled
  function invariant_availableForWithdrawalInMAICorrectlyScaled() public {
    uint256 availableUnderlying = psm.availableForWithdrawal();
    uint256 availableMAI = psm.availableForWithdrawalInMAI();

    // decimalDifference is 12 (18 - 6) for USDC->MAI
    assertEq(availableMAI, availableUnderlying * 10 ** 12, 'INVARIANT VIOLATED: MAI scaling incorrect');
  }

  /// @notice Log handler stats after invariant run
  function invariant_callSummary() public view {
    console.log('--- Handler Call Summary ---');
    console.log('Total deposited:', handler.ghost_totalDeposited());
    console.log('Total scheduled:', handler.ghost_totalWithdrawnScheduled());
    console.log('Total executed:', handler.ghost_totalWithdrawnExecuted());
    console.log('Deposit count:', handler.ghost_depositCount());
    console.log('Schedule count:', handler.ghost_scheduleCount());
    console.log('Withdraw count:', handler.ghost_withdrawCount());
    console.log('PSM total stable:', psm.totalStableLiquidity());
    console.log('PSM total queued:', psm.totalQueuedLiquidity());
    console.log('PSM min reserves:', psm.minimumReserves());
    console.log('PSM available:', psm.availableForWithdrawal());
  }
}

/// @title BeefyVaultMainnetInvariantZeroReserves
/// @notice Invariant tests with zero minimum reserves (baseline behavior)
contract BeefyVaultMainnetInvariantZeroReserves is StdInvariant, Test {
  // Use latest block for public RPCs
  // uint256 internal constant _FORK_BLOCK = 21_350_000;

  BeefyVaultPSMV2 internal psm;
  PSMHandler internal handler;

  IERC20 internal usdcToken = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
  IERC20 internal maiToken = IERC20(0x8D6CeBD76f18E1558D4DB88138e2DeFB3909fAD6);
  IERC20 internal mooToken = IERC20(0x562Ea6FfFD1293b9433E7b81A2682C31892ea013);

  // MAI whale address (owner with large balance)
  address internal constant MAI_WHALE = 0x3182E6856c3B59C39114416075770Ec9DC9Ff436;

  /// @notice Helper to deal tokens by writing directly to storage or transferring from whale
  /// @dev USDC uses slot 9 for balances, MAI uses whale transfer due to non-standard storage
  function _dealToken(address token, address to, uint256 amount) internal {
    if (token == address(maiToken)) {
      // MAI has non-standard storage layout, transfer from whale instead
      vm.prank(MAI_WHALE);
      IERC20(token).transfer(to, amount);
    } else {
      // USDC uses slot 9 for balances
      uint256 slot;
      if (token == address(usdcToken)) {
        slot = 9; // USDC balance slot
      } else {
        slot = 0; // Standard ERC20 balance slot
      }
      bytes32 storageSlot = keccak256(abi.encode(to, slot));
      vm.store(token, storageSlot, bytes32(amount));
    }
  }

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl('mainnet'));

    address owner = makeAddr('owner');
    vm.startPrank(owner);

    psm = new BeefyVaultPSMV2();
    vm.stopPrank();
    // Note: Whale has ~7M MAI, so we use 5M to leave buffer for actors
    _dealToken(address(maiToken), address(psm), 5_000_000 * 10 ** 18);
    vm.startPrank(owner);
    psm.initialize(address(mooToken), 100, 100, address(maiToken));

    // Keep minimum reserves at 0 (default)
    // This tests backward compatibility with original behavior

    vm.stopPrank();

    handler = new PSMHandler(psm, usdcToken, maiToken);

    targetContract(address(handler));

    bytes4[] memory selectors = new bytes4[](4);
    selectors[0] = PSMHandler.deposit.selector;
    selectors[1] = PSMHandler.scheduleWithdraw.selector;
    selectors[2] = PSMHandler.withdraw.selector;
    selectors[3] = PSMHandler.warpTime.selector;

    targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
  }

  /// @notice INVARIANT: With zero reserves, available liquidity still respects the fee-floor clamp
  function invariant_zeroReservesAllLiquidityAvailable() public {
    uint256 totalStable = psm.totalStableLiquidity();
    uint256 totalQueued = psm.totalQueuedLiquidity();
    uint256 available = psm.availableForWithdrawal();
    uint256 expectedAvailable;

    if (totalStable > totalQueued) {
      uint256 netAvailable = totalStable - totalQueued;
      if (netAvailable > psm.calculateFee(netAvailable, false)) {
        expectedAvailable = netAvailable;
      }
    }

    assertEq(available, expectedAvailable, 'With zero reserves, available should reflect the fee-floor clamp');
  }

  /// @notice INVARIANT: Queued never exceeds total
  function invariant_queuedNeverExceedsTotal() public {
    assertLe(psm.totalQueuedLiquidity(), psm.totalStableLiquidity(), 'Queued should never exceed total');
  }
}
