// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {Test} from 'forge-std/Test.sol';

import {AaveUSDPSMV1} from 'contracts/AaveUSDPSM/V1.sol';
import {AaveLocalPoly} from './AaveLocalPoly.sol';

contract AaveUSDPSMEvacuateAndSweepTest is AaveLocalPoly {
  address internal guardian = makeAddr('guardian');

  function setUp() public override {
    super.setUp();
    vm.startPrank(_owner);
    _psm.setGuardian(guardian, true);
  }

  function _depositAs(address user, uint256 amount) internal {
    vm.stopPrank();
    _usdcMock.mint(user, amount);
    vm.startPrank(user);
    _usdcMock.approve(address(_psm), amount);
    _psm.deposit(amount);
    vm.stopPrank();
    vm.startPrank(_owner);
  }

  function _scheduleWithdrawAs(address user, uint256 maiAmount) internal {
    vm.stopPrank();
    _maiMock.mint(user, maiAmount);
    vm.startPrank(user);
    _maiMock.approve(address(_psm), maiAmount);
    _psm.scheduleWithdraw(maiAmount);
    vm.stopPrank();
    vm.startPrank(_owner);
  }

  // --- evacuate ---

  function test_evacuate_drainsATokenAndFreezes() public {
    _depositAs(_user, 10_000 * 10 ** 6);

    uint256 aTokenPre = _aToken.balanceOf(address(_psm));
    assertGt(aTokenPre, 0);

    vm.stopPrank();
    vm.prank(guardian);
    _psm.evacuateVault();

    assertTrue(_psm.evacuated(), 'evacuated flag');
    assertEq(_psm.evacuationTime(), block.timestamp, 'evacuationTime recorded');
    assertTrue(_psm.stopped(), 'stopped flag');
    assertEq(_psm.upgradeTime(), block.timestamp + 2 days, 'upgradeTime set');
    assertEq(_aToken.balanceOf(address(_psm)), 0, 'aToken drained');
    assertEq(_usdcMock.balanceOf(address(_psm)), aTokenPre, 'USDC landed on PSM');
  }

  function test_evacuate_catchesPoolRevertAndStillFreezes() public {
    _depositAs(_user, 5_000 * 10 ** 6);

    _poolMock.setRevertOnWithdraw(true);

    uint256 aTokenPre = _aToken.balanceOf(address(_psm));
    uint256 usdcPre = _usdcMock.balanceOf(address(_psm));

    vm.stopPrank();
    vm.prank(guardian);
    _psm.evacuateVault();

    assertTrue(_psm.evacuated(), 'still frozen despite withdraw revert');
    assertEq(_aToken.balanceOf(address(_psm)), aTokenPre, 'aToken unchanged (withdraw reverted)');
    assertEq(_usdcMock.balanceOf(address(_psm)), usdcPre, 'no USDC transferred');
  }

  function test_evacuate_revertsForNonGuardianCaller() public {
    _depositAs(_user, 1_000 * 10 ** 6);
    vm.stopPrank();
    vm.prank(_user);
    vm.expectRevert(AaveUSDPSMV1.CallerIsNotGuardianOrOwner.selector);
    _psm.evacuateVault();
  }

  // --- claimRefund / forceSettle ---

  function test_claimRefund_refundsQueuedMAIPostEvac() public {
    _depositAs(_user, 100_000 * 10 ** 6);

    uint256 withdrawMAI = 40_000 * 10 ** 18;
    _scheduleWithdrawAs(_user, withdrawMAI);

    vm.stopPrank();
    vm.prank(guardian);
    _psm.evacuateVault();

    uint256 userMaiBefore = _maiMock.balanceOf(_user);

    vm.prank(_user);
    _psm.claimRefund();

    assertEq(_maiMock.balanceOf(_user), userMaiBefore + withdrawMAI, 'user receives full queued MAI');
    assertEq(_psm.scheduledWithdrawalAmount(_user), 0, 'queue cleared');
    assertEq(_psm.withdrawalEpoch(_user), 0, 'epoch cleared');
    assertEq(_psm.totalQueuedMAI(), 0, 'totalQueuedMAI drained');
    assertEq(_psm.totalQueuedLiquidity(), 0, 'totalQueuedLiquidity drained');
  }

  function test_claimRefund_revertsBeforeEvac() public {
    _depositAs(_user, 10_000 * 10 ** 6);
    _scheduleWithdrawAs(_user, 1_000 * 10 ** 18);

    vm.stopPrank();
    vm.prank(_user);
    vm.expectRevert(AaveUSDPSMV1.NotEvacuated.selector);
    _psm.claimRefund();
  }

  function test_forceSettle_paysUserAfterTimeout() public {
    _depositAs(_user, 100_000 * 10 ** 6);
    _scheduleWithdrawAs(_user, 10_000 * 10 ** 18);

    vm.stopPrank();
    vm.prank(guardian);
    _psm.evacuateVault();

    // Before timeout: forceSettle reverts.
    vm.prank(_owner);
    vm.expectRevert(AaveUSDPSMV1.SettlementTooEarly.selector);
    _psm.forceSettle(_user);

    vm.warp(block.timestamp + _psm.SETTLEMENT_TIMEOUT() + 1);

    uint256 userMaiBefore = _maiMock.balanceOf(_user);
    vm.prank(_owner);
    _psm.forceSettle(_user);
    assertEq(_maiMock.balanceOf(_user), userMaiBefore + 10_000 * 10 ** 18, 'user paid via forceSettle');
  }

  // --- sweep ---

  function test_sweep_resuppliesIdleUSDC() public {
    _depositAs(_user, 1_000 * 10 ** 6);

    uint256 idle = 500 * 10 ** 6;
    _usdcMock.mint(address(_psm), idle);

    uint256 tslPre = _psm.totalStableLiquidity();
    uint256 aTokenPre = _aToken.balanceOf(address(_psm));

    _psm.sweep();

    assertEq(_usdcMock.balanceOf(address(_psm)), 0, 'idle USDC consumed');
    assertEq(_psm.totalStableLiquidity(), tslPre + idle, 'totalStableLiquidity grew');
    assertEq(_aToken.balanceOf(address(_psm)), aTokenPre + idle, 'aToken minted for sweep');
  }

  function test_sweep_revertsPostEvac() public {
    _depositAs(_user, 1_000 * 10 ** 6);
    _usdcMock.mint(address(_psm), 500 * 10 ** 6);

    vm.stopPrank();
    vm.prank(guardian);
    _psm.evacuateVault();

    vm.prank(_owner);
    vm.expectRevert(AaveUSDPSMV1.ContractIsPaused.selector);
    _psm.sweep();
  }

  function test_sweep_revertsOnZeroBalance() public {
    vm.expectRevert(AaveUSDPSMV1.InvalidAmount.selector);
    _psm.sweep();
  }

  // --- guardian admin ---

  function test_setGuardian_addAndRevoke() public {
    address other = makeAddr('other');
    _psm.setGuardian(other, true);
    assertTrue(_psm.guardians(other));

    _psm.setGuardian(other, false);
    assertFalse(_psm.guardians(other));
  }

  function test_setGuardian_rejectsZeroAddressOnEnable() public {
    vm.expectRevert(AaveUSDPSMV1.GuardianCannotBeZeroAddress.selector);
    _psm.setGuardian(address(0), true);
  }
}
