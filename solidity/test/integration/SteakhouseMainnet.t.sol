// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {BeefyVaultPSMV2} from 'contracts/BeefyVaultPSM/V2.sol';
import {MainnetIntegrationBase} from './MainnetIntegrationBase.sol';

/// @title SteakhouseMainnet
/// @notice Integration tests for Beefy Steakhouse Smokehouse vault PSM on Ethereum mainnet
contract SteakhouseMainnet is MainnetIntegrationBase {
  // Uses default _mooTokenAddress() which returns Smokehouse: 0x562Ea6FfFD1293b9433E7b81A2682C31892ea013

  function test_deposit_convertsUsdcToMai() public {
    uint256 depositAmount = 1000 * 10 ** 6; // 1000 USDC
    _usdcToken.approve(address(_psm), depositAmount);

    uint256 maiBefore = _maiToken.balanceOf(_owner);
    _psm.deposit(depositAmount);
    uint256 maiAfter = _maiToken.balanceOf(_owner);

    uint256 fee = _psm.calculateFee(depositAmount, true);
    uint256 expectedMAI = (depositAmount - fee) * 10 ** 12;
    assertEq(maiAfter - maiBefore, expectedMAI, 'MAI received should match deposit minus fee');
  }

  function test_scheduleWithdraw_locksForThreeDays() public {
    uint256 depositAmount = 1000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    uint256 withdrawMAI = 100 * 10 ** 18;
    _maiToken.approve(address(_psm), withdrawMAI);
    _psm.scheduleWithdraw(withdrawMAI);

    uint256 epoch = _psm.withdrawalEpoch(_owner);
    assertEq(epoch, block.timestamp + 3 days, 'Withdrawal epoch should be 3 days from now');
    assertEq(_psm.scheduledWithdrawalAmount(_owner), withdrawMAI, 'Scheduled amount should match');
  }

  function test_withdraw_afterEpoch_returnsUsdc() public {
    uint256 depositAmount = 1000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    uint256 withdrawMAI = 100 * 10 ** 18;
    _maiToken.approve(address(_psm), withdrawMAI);
    _psm.scheduleWithdraw(withdrawMAI);

    vm.warp(block.timestamp + 3 days + 1);

    uint256 usdcBefore = _usdcToken.balanceOf(_owner);
    _psm.withdraw();
    uint256 usdcAfter = _usdcToken.balanceOf(_owner);

    assertGt(usdcAfter, usdcBefore, 'User should have received USDC');
  }

  function test_withdraw_beforeEpoch_reverts() public {
    uint256 depositAmount = 1000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    uint256 withdrawMAI = 100 * 10 ** 18;
    _maiToken.approve(address(_psm), withdrawMAI);
    _psm.scheduleWithdraw(withdrawMAI);

    vm.warp(block.timestamp + 1 days);

    vm.expectRevert(BeefyVaultPSMV2.WithdrawalNotAvailable.selector);
    _psm.withdraw();
  }

  function test_feeCalculation_minimumFeeApplied() public {
    uint256 amount = 50 * 10 ** 6;
    uint256 fee = _psm.calculateFee(amount, false);
    assertEq(fee, 1_000_000, 'Fee should be $1 minimum (1_000_000)');
  }

  function test_feeCalculation_percentageFeeApplied() public {
    uint256 amount = 500 * 10 ** 6;
    uint256 fee = _psm.calculateFee(amount, false);
    uint256 expectedFee = 500 * 10 ** 6 * 100 / 10_000;
    assertEq(fee, expectedFee, 'Fee should be percentage-based');
  }

  function test_deposit_exceedsMaxDeposit_reverts() public {
    uint256 tooMuch = 1e24 + 1;
    _dealToken(address(_usdcToken), _owner, tooMuch);
    vm.startPrank(_owner);
    _usdcToken.approve(address(_psm), tooMuch);

    vm.expectRevert(BeefyVaultPSMV2.InvalidAmount.selector);
    _psm.deposit(tooMuch);
  }

  function test_deposit_belowMinimumAmount_reverts() public {
    uint256 tooSmall = 1_000_000;
    _usdcToken.approve(address(_psm), tooSmall);

    vm.expectRevert(BeefyVaultPSMV2.InvalidAmount.selector);
    _psm.deposit(tooSmall);
  }

  function test_deposit_insufficientMaiBalance_reverts() public {
    BeefyVaultPSMV2 emptyPsm = new BeefyVaultPSMV2();
    emptyPsm.initialize(address(_mooToken), 100, 100, address(_maiToken));

    uint256 depositAmount = 1000 * 10 ** 6;
    _usdcToken.approve(address(emptyPsm), depositAmount);

    vm.expectRevert(BeefyVaultPSMV2.InsufficientMAIBalance.selector);
    emptyPsm.deposit(depositAmount);
  }
}
