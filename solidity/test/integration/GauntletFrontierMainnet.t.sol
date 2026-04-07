// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {BeefyVaultPSMV2} from 'contracts/BeefyVaultPSM/V2.sol';
import {MainnetIntegrationBase} from './MainnetIntegrationBase.sol';

/// @title GauntletFrontierMainnet
/// @notice Integration tests for Beefy Gauntlet Frontier vault PSM on Ethereum mainnet
contract GauntletFrontierMainnet is MainnetIntegrationBase {
  function _mooTokenAddress() internal pure override returns (address) {
    return 0x16F06dE7F077A95684DBAeEdD15A5808c3E13cD0; // Moo Morpho Gauntlet Frontier USDC
  }

  function test_deposit_convertsUsdcToMai() public {
    uint256 depositAmount = 1000 * 10 ** 6; // 1000 USDC
    _usdcToken.approve(address(_psm), depositAmount);

    uint256 maiBefore = _maiToken.balanceOf(_owner);
    _psm.deposit(depositAmount);
    uint256 maiAfter = _maiToken.balanceOf(_owner);

    // With 1% fee (test base uses 100 bps), user gets 990 USDC worth of MAI
    uint256 fee = _psm.calculateFee(depositAmount, true);
    uint256 expectedMAI = (depositAmount - fee) * 10 ** 12;
    assertEq(maiAfter - maiBefore, expectedMAI, 'MAI received should match deposit minus fee');
  }

  function test_scheduleWithdraw_locksForThreeDays() public {
    // Deposit first
    uint256 depositAmount = 1000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    // Schedule withdrawal
    uint256 withdrawMAI = 100 * 10 ** 18;
    _maiToken.approve(address(_psm), withdrawMAI);
    _psm.scheduleWithdraw(withdrawMAI);

    // Verify epoch is set to 3 days from now
    uint256 epoch = _psm.withdrawalEpoch(_owner);
    assertEq(epoch, block.timestamp + 3 days, 'Withdrawal epoch should be 3 days from now');
    assertEq(_psm.scheduledWithdrawalAmount(_owner), withdrawMAI, 'Scheduled amount should match');
  }

  function test_withdraw_afterEpoch_returnsUsdc() public {
    // Deposit
    uint256 depositAmount = 1000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    // Schedule withdrawal
    uint256 withdrawMAI = 100 * 10 ** 18;
    _maiToken.approve(address(_psm), withdrawMAI);
    _psm.scheduleWithdraw(withdrawMAI);

    // Warp past 3-day delay
    vm.warp(block.timestamp + 3 days + 1);

    // Execute withdrawal
    uint256 usdcBefore = _usdcToken.balanceOf(_owner);
    _psm.withdraw();
    uint256 usdcAfter = _usdcToken.balanceOf(_owner);

    // User should receive USDC minus withdrawal fee
    assertGt(usdcAfter, usdcBefore, 'User should have received USDC');
  }

  function test_withdraw_beforeEpoch_reverts() public {
    // Deposit
    uint256 depositAmount = 1000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    // Schedule withdrawal
    uint256 withdrawMAI = 100 * 10 ** 18;
    _maiToken.approve(address(_psm), withdrawMAI);
    _psm.scheduleWithdraw(withdrawMAI);

    // Try to withdraw before epoch (only warp 1 day)
    vm.warp(block.timestamp + 1 days);

    vm.expectRevert(BeefyVaultPSMV2.WithdrawalNotAvailable.selector);
    _psm.withdraw();
  }

  function test_feeCalculation_minimumFeeApplied() public {
    // With 100 bps (1%) withdrawal fee, $1 minimum kicks in below $100 withdrawal
    // Withdraw 50 USDC worth: 1% of 50 = $0.50, but minimum is $1
    uint256 amount = 50 * 10 ** 6;
    uint256 fee = _psm.calculateFee(amount, false);
    assertEq(fee, 1_000_000, 'Fee should be $1 minimum (1_000_000)');
  }

  function test_feeCalculation_percentageFeeApplied() public {
    // Withdraw 500 USDC worth: 1% of 500 = $5, which is > $1 minimum
    uint256 amount = 500 * 10 ** 6;
    uint256 fee = _psm.calculateFee(amount, false);
    uint256 expectedFee = 500 * 10 ** 6 * 100 / 10_000; // 1% = 5 USDC
    assertEq(fee, expectedFee, 'Fee should be percentage-based');
  }

  function test_deposit_exceedsMaxDeposit_reverts() public {
    // maxDeposit is 1e24, try to deposit more
    uint256 tooMuch = 1e24 + 1;
    _dealToken(address(_usdcToken), _owner, tooMuch);
    vm.startPrank(_owner);
    _usdcToken.approve(address(_psm), tooMuch);

    vm.expectRevert(BeefyVaultPSMV2.InvalidAmount.selector);
    _psm.deposit(tooMuch);
  }

  function test_deposit_belowMinimumAmount_reverts() public {
    // minimumDepositFee is 1_000_000 ($1), deposit must be > that
    uint256 tooSmall = 1_000_000; // exactly $1, needs to be strictly greater
    _usdcToken.approve(address(_psm), tooSmall);

    vm.expectRevert(BeefyVaultPSMV2.InvalidAmount.selector);
    _psm.deposit(tooSmall);
  }

  function test_deposit_insufficientMaiBalance_reverts() public {
    // Deploy a fresh PSM with no MAI funding
    BeefyVaultPSMV2 emptyPsm = new BeefyVaultPSMV2();
    emptyPsm.initialize(address(_mooToken), 100, 100, address(_maiToken));

    uint256 depositAmount = 1000 * 10 ** 6;
    _usdcToken.approve(address(emptyPsm), depositAmount);

    vm.expectRevert(BeefyVaultPSMV2.InsufficientMAIBalance.selector);
    emptyPsm.deposit(depositAmount);
  }
}
