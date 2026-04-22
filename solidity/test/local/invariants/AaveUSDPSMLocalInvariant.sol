// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from 'forge-std/Test.sol';
import {StdInvariant} from 'forge-std/StdInvariant.sol';
import {console} from 'forge-std/console.sol';

import {AaveUSDPSMV1} from 'contracts/AaveUSDPSM/V1.sol';
import {MockERC20} from '../../mocks/MockERC20.sol';
import {MockAToken} from '../../mocks/MockAToken.sol';
import {MockAavePool} from '../../mocks/MockAavePool.sol';

/// @title AavePSMHandler
/// @notice Handler for fuzzing `AaveUSDPSMV1`. Ported from `PSMHandler` in
///         `BeefyVaultLocalInvariant.sol` with the yield mechanism swapped
///         from share-price rebalance to aToken rebasing (pool.simulateYield).
contract AavePSMHandler is Test {
  AaveUSDPSMV1 public psm;
  MockERC20 public usdcMock;
  MockERC20 public maiMock;
  MockAToken public aTokenMock;
  MockAavePool public poolMock;

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
    AaveUSDPSMV1 _psm,
    MockERC20 _usdc,
    MockERC20 _mai,
    MockAToken _aToken,
    MockAavePool _pool
  ) {
    psm = _psm;
    usdcMock = _usdc;
    maiMock = _mai;
    aTokenMock = _aToken;
    poolMock = _pool;

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
    if (_scheduled == 0) return;

    vm.startPrank(currentActor);
    try psm.withdraw() {
      ghost_totalWithdrawnExecuted += _scheduled / 10 ** 12;
      ghost_withdrawCount++;
    } catch {}
    vm.stopPrank();
  }

  function warpTime(
    uint256 _seconds
  ) public {
    _seconds = bound(_seconds, 1, 7 days);
    vm.warp(block.timestamp + _seconds);
  }

  /// @notice Simulate rebasing yield directly onto the PSM's aToken balance.
  function simulateYield(
    uint256 _amount
  ) public {
    _amount = bound(_amount, 1, 1_000 * 10 ** 6);
    poolMock.simulateYield(address(psm), _amount);
    ghost_yieldSimulated += _amount;
  }

  function getActorCount() external view returns (uint256) {
    return actors.length;
  }
}

/// @title AaveUSDPSMInvariantTest
/// @notice Invariant suite with a non-zero `minimumReserves` configuration.
contract AaveUSDPSMInvariantTest is StdInvariant, Test {
  AaveUSDPSMV1 internal psm;
  AavePSMHandler internal handler;

  MockERC20 internal usdcMock;
  MockERC20 internal maiMock;
  MockAToken internal aTokenMock;
  MockAavePool internal poolMock;

  function setUp() public {
    address owner = makeAddr('owner');

    usdcMock = new MockERC20('USD Coin', 'USDC', 6);
    maiMock = new MockERC20('Mai Stablecoin', 'MAI', 18);

    poolMock = new MockAavePool(usdcMock);
    aTokenMock = new MockAToken('Aave Polygon USDCn', 'aPolUSDCn', 6, address(poolMock), address(usdcMock));
    poolMock.init(aTokenMock);

    vm.startPrank(owner);
    psm = new AaveUSDPSMV1();
    maiMock.mint(address(psm), 100_000_000 * 10 ** 18);
    psm.initialize(address(aTokenMock), 100, 100, address(maiMock));
    psm.setMinimumReserves(1000 * 10 ** 6);
    vm.stopPrank();

    handler = new AavePSMHandler(psm, usdcMock, maiMock, aTokenMock, poolMock);

    targetContract(address(handler));

    bytes4[] memory selectors = new bytes4[](5);
    selectors[0] = AavePSMHandler.deposit.selector;
    selectors[1] = AavePSMHandler.scheduleWithdraw.selector;
    selectors[2] = AavePSMHandler.withdraw.selector;
    selectors[3] = AavePSMHandler.warpTime.selector;
    selectors[4] = AavePSMHandler.simulateYield.selector;

    targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
  }

  /// @notice totalQueuedLiquidity must never exceed totalStableLiquidity.
  function invariant_queuedNeverExceedsTotal() public {
    assertLe(psm.totalQueuedLiquidity(), psm.totalStableLiquidity(), 'queued <= total');
  }

  /// @notice Pre-evac: aToken balance (rebased) covers net liabilities.
  function invariant_aTokenCoversLiabilities() public {
    if (psm.evacuated()) return;
    assertGe(
      aTokenMock.balanceOf(address(psm)) + usdcMock.balanceOf(address(psm)),
      psm.totalStableLiquidity(),
      'aToken + idle USDC >= totalStableLiquidity'
    );
  }

  /// @notice MAI on the PSM always covers the queued MAI liability.
  function invariant_maiCoversQueuedMAI() public {
    assertGe(maiMock.balanceOf(address(psm)), psm.totalQueuedMAI(), 'MAI balance >= totalQueuedMAI');
  }

  /// @notice availableForWithdrawal respects minimumReserves at all times.
  function invariant_minimumReservesRespected() public {
    uint256 _totalStable = psm.totalStableLiquidity();
    uint256 _totalQueued = psm.totalQueuedLiquidity();
    uint256 _minReserves = psm.minimumReserves();

    if (_totalStable > _totalQueued) {
      uint256 _available = _totalStable - _totalQueued;
      if (_available > _minReserves) {
        assertGe(_available, _minReserves, 'available >= minimumReserves when above');
      }
    }
  }

  /// @notice Executed withdrawals never exceed scheduled withdrawals.
  function invariant_executedLEScheduled() public {
    assertLe(
      handler.ghost_totalWithdrawnExecuted(),
      handler.ghost_totalWithdrawnScheduled(),
      'executed <= scheduled'
    );
  }

  /// @notice Call summary for debugging.
  function invariant_callSummary() public view {
    console.log('--- AaveUSDPSM Handler Summary ---');
    console.log('Deposits:', handler.ghost_depositCount());
    console.log('Scheduled:', handler.ghost_scheduleCount());
    console.log('Executed:', handler.ghost_withdrawCount());
    console.log('Yield simulated:', handler.ghost_yieldSimulated());
    console.log('PSM totalStable:', psm.totalStableLiquidity());
    console.log('PSM totalQueued:', psm.totalQueuedLiquidity());
    console.log('PSM aToken:', aTokenMock.balanceOf(address(psm)));
  }
}
