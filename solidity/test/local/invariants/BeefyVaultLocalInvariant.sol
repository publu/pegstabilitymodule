// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from 'forge-std/Test.sol';
import {StdInvariant} from 'forge-std/StdInvariant.sol';
import {BeefyVaultPSMV2} from 'contracts/BeefyVaultPSM/V2.sol';
import {console} from 'forge-std/console.sol';
import {MockERC20} from '../../mocks/MockERC20.sol';
import {MockBeefyVault} from '../../mocks/MockBeefyVault.sol';

/// @title PSMHandler
/// @notice Handler contract for invariant testing — exposes bounded actions
///         against `BeefyVaultPSM/V2`. Replaces the fork-based `PSMHandler` that
///         used whale transfers + vm.store slot 9 for MAI/USDC funding; now
///         uses `MockERC20.mint()` directly and exposes a `simulateYield`
///         action so invariants exercise share-price-changes-over-time.
contract PSMHandler is Test {
  BeefyVaultPSMV2 public psm;
  MockERC20 public usdcMock;
  MockERC20 public maiMock;
  MockBeefyVault public beefyMock;

  address[] public actors;
  address internal currentActor;

  uint256 public ghost_totalDeposited;
  uint256 public ghost_totalWithdrawnScheduled;
  uint256 public ghost_totalWithdrawnExecuted;
  uint256 public ghost_depositCount;
  uint256 public ghost_scheduleCount;
  uint256 public ghost_withdrawCount;
  uint256 public ghost_yieldSimulated;

  constructor(
    BeefyVaultPSMV2 _psm,
    MockERC20 _usdc,
    MockERC20 _mai,
    MockBeefyVault _beefy
  ) {
    psm = _psm;
    usdcMock = _usdc;
    maiMock = _mai;
    beefyMock = _beefy;

    for (uint256 i = 0; i < 10; i++) {
      actors.push(makeAddr(string(abi.encodePacked('actor', i))));
    }
  }

  function deposit(
    uint256 _actorIndex,
    uint256 _amount
  ) public {
    currentActor = actors[_actorIndex % actors.length];
    _amount = bound(_amount, psm.minimumDepositFee() + 1, 100_000 * 10 ** 6);

    usdcMock.mint(currentActor, _amount);
    vm.startPrank(currentActor);
    usdcMock.approve(address(psm), _amount);

    try psm.deposit(_amount) {
      ghost_totalDeposited += _amount;
      ghost_depositCount++;
    } catch {}
    vm.stopPrank();
  }

  function scheduleWithdraw(
    uint256 _actorIndex,
    uint256 _amount
  ) public {
    currentActor = actors[_actorIndex % actors.length];

    if (psm.withdrawalEpoch(currentActor) != 0) return;

    uint256 _available = psm.availableForWithdrawalInMAI();
    if (_available == 0) return;

    uint256 _minWithdraw = psm.minimumWithdrawalFee();
    if (_available < _minWithdraw) return;

    _amount = bound(_amount, _minWithdraw, _available);

    maiMock.mint(currentActor, _amount);
    vm.startPrank(currentActor);
    maiMock.approve(address(psm), _amount);

    try psm.scheduleWithdraw(_amount) {
      ghost_totalWithdrawnScheduled += _amount / 10 ** 12;
      ghost_scheduleCount++;
    } catch {}
    vm.stopPrank();
  }

  function withdraw(
    uint256 _actorIndex
  ) public {
    currentActor = actors[_actorIndex % actors.length];

    if (psm.withdrawalEpoch(currentActor) == 0) return;
    if (block.timestamp < psm.withdrawalEpoch(currentActor)) {
      vm.warp(psm.withdrawalEpoch(currentActor));
    }

    uint256 _scheduled = psm.scheduledWithdrawalAmount(currentActor);

    vm.startPrank(currentActor);
    try psm.withdraw() {
      ghost_totalWithdrawnExecuted += _scheduled / 10 ** 12;
      ghost_withdrawCount++;
    } catch {}
    vm.stopPrank();
  }

  function warpTime(
    uint256 _secondsToWarp
  ) public {
    _secondsToWarp = bound(_secondsToWarp, 0, 7 days);
    vm.warp(block.timestamp + _secondsToWarp);
  }

  /// @notice Inflate the Beefy mock's underlying balance to exercise invariant
  ///         behavior under yield accrual / share-price drift. Mirrors the
  ///         Unit 6 plan directive to add simulateYield calls in the handler
  ///         so invariants see realistic state trajectories.
  function simulateYield(
    uint256 _amount
  ) public {
    _amount = bound(_amount, 0, 100_000 * 10 ** 6);
    if (_amount == 0) return;
    beefyMock.simulateYield(_amount);
    ghost_yieldSimulated += _amount;
  }

  function getActorCount() external view returns (uint256) {
    return actors.length;
  }
}

/// @title BeefyVaultMainnetInvariantTest
/// @notice Invariant tests for the mainnet PSM with a positive minimum-reserves
///         configuration. Same five invariants as the fork version; setup
///         deploys mocks locally and runs with no RPC.
contract BeefyVaultMainnetInvariantTest is StdInvariant, Test {
  BeefyVaultPSMV2 internal psm;
  PSMHandler internal handler;

  MockERC20 internal usdcMock;
  MockERC20 internal maiMock;
  MockBeefyVault internal beefyMock;

  function setUp() public {
    address owner = makeAddr('owner');

    usdcMock = new MockERC20('USD Coin', 'USDC', 6);
    maiMock = new MockERC20('Mai Stablecoin', 'MAI', 18);
    beefyMock = new MockBeefyVault(usdcMock, 18, 1e18);

    vm.startPrank(owner);
    psm = new BeefyVaultPSMV2();
    maiMock.mint(address(psm), 100_000_000 * 10 ** 18);
    psm.initialize(address(beefyMock), 100, 100, address(maiMock));
    psm.approveBeef();
    psm.setMinimumReserves(1000 * 10 ** 6); // 1000 USDC minimum reserves
    vm.stopPrank();

    handler = new PSMHandler(psm, usdcMock, maiMock, beefyMock);

    targetContract(address(handler));

    bytes4[] memory selectors = new bytes4[](5);
    selectors[0] = PSMHandler.deposit.selector;
    selectors[1] = PSMHandler.scheduleWithdraw.selector;
    selectors[2] = PSMHandler.withdraw.selector;
    selectors[3] = PSMHandler.warpTime.selector;
    selectors[4] = PSMHandler.simulateYield.selector;

    targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
  }

  /// @notice INVARIANT: Available liquidity must never go below minimum reserves after scheduling
  function invariant_minimumReservesRespected() public {
    uint256 _totalStable = psm.totalStableLiquidity();
    uint256 _totalQueued = psm.totalQueuedLiquidity();
    uint256 _minReserves = psm.minimumReserves();

    uint256 _availableLiquidity = _totalStable - _totalQueued;

    // Either there's enough liquidity to cover minimum reserves, OR total
    // liquidity is less than minimum (edge case when min reserves set after deposits)
    bool _reservesRespected = _availableLiquidity >= _minReserves || _totalStable < _minReserves;

    assertTrue(_reservesRespected, 'INVARIANT VIOLATED: Minimum reserves breached');
  }

  /// @notice INVARIANT: Total queued liquidity cannot exceed total stable liquidity
  function invariant_queuedNeverExceedsTotal() public {
    assertLe(psm.totalQueuedLiquidity(), psm.totalStableLiquidity(), 'INVARIANT VIOLATED: Queued exceeds total');
  }

  /// @notice INVARIANT: availableForWithdrawal() matches the contract's reserve and fee-floor logic
  function invariant_availableForWithdrawalCorrect() public {
    uint256 _available = psm.availableForWithdrawal();
    uint256 _totalStable = psm.totalStableLiquidity();
    uint256 _totalQueued = psm.totalQueuedLiquidity();
    uint256 _minReserves = psm.minimumReserves();

    uint256 _availableLiquidity = _totalStable - _totalQueued;
    uint256 _expectedAvailable;

    if (_availableLiquidity > _minReserves) {
      uint256 _netAvailable = _availableLiquidity - _minReserves;
      if (_netAvailable > psm.calculateFee(_netAvailable, false)) {
        _expectedAvailable = _netAvailable;
      }
    }

    assertEq(_available, _expectedAvailable, 'INVARIANT VIOLATED: Available calculation incorrect');
  }

  /// @notice INVARIANT: availableForWithdrawalInMAI is correctly scaled
  function invariant_availableForWithdrawalInMAICorrectlyScaled() public {
    uint256 _availableUnderlying = psm.availableForWithdrawal();
    uint256 _availableMAI = psm.availableForWithdrawalInMAI();

    // decimalDifference is 12 (18 - 6) for USDC->MAI
    assertEq(_availableMAI, _availableUnderlying * 10 ** 12, 'INVARIANT VIOLATED: MAI scaling incorrect');
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
    console.log('Yield simulated:', handler.ghost_yieldSimulated());
    console.log('PSM total stable:', psm.totalStableLiquidity());
    console.log('PSM total queued:', psm.totalQueuedLiquidity());
    console.log('PSM min reserves:', psm.minimumReserves());
    console.log('PSM available:', psm.availableForWithdrawal());
  }
}

/// @title BeefyVaultMainnetInvariantZeroReserves
/// @notice Invariant tests with zero minimum reserves (baseline behavior).
contract BeefyVaultMainnetInvariantZeroReserves is StdInvariant, Test {
  BeefyVaultPSMV2 internal psm;
  PSMHandler internal handler;

  MockERC20 internal usdcMock;
  MockERC20 internal maiMock;
  MockBeefyVault internal beefyMock;

  function setUp() public {
    address owner = makeAddr('owner');

    usdcMock = new MockERC20('USD Coin', 'USDC', 6);
    maiMock = new MockERC20('Mai Stablecoin', 'MAI', 18);
    beefyMock = new MockBeefyVault(usdcMock, 18, 1e18);

    vm.startPrank(owner);
    psm = new BeefyVaultPSMV2();
    maiMock.mint(address(psm), 100_000_000 * 10 ** 18);
    psm.initialize(address(beefyMock), 100, 100, address(maiMock));
    psm.approveBeef();
    // Keep minimum reserves at 0 (default) — tests backward compatibility
    vm.stopPrank();

    handler = new PSMHandler(psm, usdcMock, maiMock, beefyMock);

    targetContract(address(handler));

    bytes4[] memory selectors = new bytes4[](5);
    selectors[0] = PSMHandler.deposit.selector;
    selectors[1] = PSMHandler.scheduleWithdraw.selector;
    selectors[2] = PSMHandler.withdraw.selector;
    selectors[3] = PSMHandler.warpTime.selector;
    selectors[4] = PSMHandler.simulateYield.selector;

    targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
  }

  /// @notice INVARIANT: With zero reserves, available liquidity still respects the fee-floor clamp
  function invariant_zeroReservesAllLiquidityAvailable() public {
    uint256 _totalStable = psm.totalStableLiquidity();
    uint256 _totalQueued = psm.totalQueuedLiquidity();
    uint256 _available = psm.availableForWithdrawal();
    uint256 _expectedAvailable;

    if (_totalStable > _totalQueued) {
      uint256 _netAvailable = _totalStable - _totalQueued;
      if (_netAvailable > psm.calculateFee(_netAvailable, false)) {
        _expectedAvailable = _netAvailable;
      }
    }

    assertEq(_available, _expectedAvailable, 'With zero reserves, available should reflect the fee-floor clamp');
  }

  /// @notice INVARIANT: Queued never exceeds total
  function invariant_queuedNeverExceedsTotal() public {
    assertLe(psm.totalQueuedLiquidity(), psm.totalStableLiquidity(), 'Queued should never exceed total');
  }
}
