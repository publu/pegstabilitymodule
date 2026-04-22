// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {Test} from 'forge-std/Test.sol';
import {console} from 'forge-std/console.sol';

import {AaveUSDPSMV1} from 'contracts/AaveUSDPSM/V1.sol';
import {IAavePool, IAToken} from 'interfaces/IAavePool.sol';

/// @title AaveUSDPSMPolygonIntegrationTest
/// @notice Single-function forktender integration test for AaveUSDPSMV1 on
///         Polygon. TU-conscious: spins up one VNet per run and exercises
///         deposit → scheduleWithdraw → withdraw → claimFees → evacuate →
///         claimRefund in sequence.
/// @dev Parked out of the default test loop. Opt in with `RUN_FORK_TESTS=1`
///      plus a working `polygon` RPC in `foundry.toml`:
///
///        RUN_FORK_TESTS=1 FOUNDRY_PROFILE=test forge test \
///          --match-contract AaveUSDPSMPolygon -vvv
contract AaveUSDPSMPolygonIntegrationTest is Test {
  // On-chain identities verified via cast 2026-04-22.
  address internal constant GEM = 0xA4D94019934D8333Ef880ABFFbF2FDd611C762BD;       // aPolUSDCn
  address internal constant USDC = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;      // native USDC
  address internal constant POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;      // Aave V3 Polygon Pool
  address internal constant MAI = 0xa3Fa99A148fA48D14Ed51d610c367C61876997F1;       // miMATIC

  address internal _user = makeAddr('user');
  address internal _owner = makeAddr('owner');
  address internal _guardian = makeAddr('guardian');

  IERC20 internal _usdc = IERC20(USDC);
  IERC20 internal _mai = IERC20(MAI);
  IAToken internal _aToken = IAToken(GEM);
  AaveUSDPSMV1 internal _psm;

  function setUp() public {
    // Forktender-only suite (see header doc). Opt-in via RUN_FORK_TESTS=1
    // so the default `forge test` loop skips it cleanly instead of choking
    // on `deal()` against real Polygon USDC proxy storage.
    if (vm.envOr('RUN_FORK_TESTS', uint256(0)) == 0) {
      vm.skip(true);
      return;
    }
    vm.createSelectFork(vm.rpcUrl('polygon'));

    vm.startPrank(_owner);

    _psm = new AaveUSDPSMV1();
    deal(address(_mai), address(_psm), 100_000_000 * 10 ** 18);
    _psm.initialize(GEM, 0, 30, MAI);
    _psm.updateMinimumFees(0, 1_000_000);
    _psm.setGuardian(_guardian, true);

    deal(address(_usdc), _user, 100_000 * 10 ** 6);
    vm.stopPrank();
  }

  function test_polygon_fullLifecycle() public {
    // --- deposit ---
    uint256 depositAmount = 10_000 * 10 ** 6;
    vm.startPrank(_user);
    _usdc.approve(address(_psm), depositAmount);

    uint256 userMaiBefore = _mai.balanceOf(_user);
    uint256 userUsdcBefore = _usdc.balanceOf(_user);
    _psm.deposit(depositAmount);

    uint256 fee = _psm.calculateFee(depositAmount, true);
    uint256 expectedMAI = (depositAmount - fee) * 10 ** 12;
    assertEq(_mai.balanceOf(_user), userMaiBefore + expectedMAI, 'MAI paid to user');
    assertEq(_usdc.balanceOf(_user), userUsdcBefore - depositAmount, 'USDC pulled from user');
    assertApproxEqAbs(_aToken.balanceOf(address(_psm)), depositAmount, 1, 'PSM holds aToken ~1:1 (1-wei Aave rounding tolerance)');

    // --- scheduleWithdraw ---
    uint256 withdrawMAI = 1_000 * 10 ** 18;
    _mai.approve(address(_psm), withdrawMAI);
    _psm.scheduleWithdraw(withdrawMAI);
    vm.stopPrank();

    // --- accrue real Aave interest, then claimFees ---
    vm.warp(block.timestamp + 30 days);

    vm.startPrank(_owner);
    uint256 ownerUsdcBefore = _usdc.balanceOf(_owner);
    _psm.claimFees();
    uint256 ownerUsdcAfter = _usdc.balanceOf(_owner);
    assertGt(ownerUsdcAfter, ownerUsdcBefore, 'owner receives real Aave yield');
    console.log('Aave yield claimed (30d):', ownerUsdcAfter - ownerUsdcBefore);
    vm.stopPrank();

    // --- execute scheduled withdraw ---
    vm.prank(_user);
    _psm.withdraw();
    uint256 expectedPayout = 1_000 * 10 ** 6 - _psm.calculateFee(1_000 * 10 ** 6, false);
    assertEq(
      _usdc.balanceOf(_user),
      userUsdcBefore - depositAmount + expectedPayout,
      'user receives net USDC'
    );

    // --- user schedules a second withdrawal we will recover via claimRefund ---
    uint256 secondWithdrawMAI = 2_000 * 10 ** 18;
    vm.startPrank(_user);
    _mai.approve(address(_psm), secondWithdrawMAI);
    _psm.scheduleWithdraw(secondWithdrawMAI);
    vm.stopPrank();

    // --- evacuate ---
    vm.prank(_guardian);
    _psm.evacuateVault();

    assertTrue(_psm.evacuated(), 'evacuated');
    assertApproxEqAbs(_aToken.balanceOf(address(_psm)), 0, 1, 'aToken drained (1-wei tolerance)');
    assertGt(_usdc.balanceOf(address(_psm)), 0, 'USDC landed on PSM');

    // --- claimRefund ---
    uint256 userMaiPreClaim = _mai.balanceOf(_user);
    vm.prank(_user);
    _psm.claimRefund();
    assertEq(_mai.balanceOf(_user), userMaiPreClaim + secondWithdrawMAI, 'user recovers queued MAI');
  }
}
