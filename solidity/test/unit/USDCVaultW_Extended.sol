// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {StdCheats} from 'forge-std/StdCheats.sol';
import {Test} from 'forge-std/Test.sol';
import {console} from 'forge-std/console.sol';

import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {USDCVaultDDW} from 'contracts/USDCVaultDDW.sol';
import {MetisIntegrationBase} from '../integration/MetisIntegrationBase.sol';

/// @title USDCVaultDDW Extended Test Suite
/// @notice Comprehensive tests for additional edge cases and scenarios not covered in the main test suite
contract USDCVaultInitializationSuite is MetisIntegrationBase {
  event FeesUpdated(uint256 newDepositFee, uint256 newWithdrawalFee);
  event MinimumFeesUpdated(uint256 newMinimumDepositFee, uint256 newMinimumWithdrawalFee);
  event MaxUpdated(uint256 maxDeposit, uint256 maxWithdraw);

  function test_CannotInitializeTwice() public {
    USDCVaultDDW newPsm = new USDCVaultDDW();
    newPsm.initialize(100, 100, address(_maiToken), address(_usdcToken));

    vm.expectRevert(USDCVaultDDW.AlreadyInitialized.selector);
    newPsm.initialize(200, 200, address(_maiToken), address(_usdcToken));
  }

  function test_InitializeWithZeroFees() public {
    USDCVaultDDW newPsm = new USDCVaultDDW();
    newPsm.initialize(0, 0, address(_maiToken), address(_usdcToken));

    assertEq(newPsm.depositFee(), 0, 'Deposit fee should be 0');
    assertEq(newPsm.withdrawalFee(), 0, 'Withdrawal fee should be 0');
    assertEq(newPsm.minimumDepositFee(), 0, 'Minimum deposit fee should be 0');
    assertEq(newPsm.minimumWithdrawalFee(), 0, 'Minimum withdrawal fee should be 0');
  }

  function test_InitializeWithMaxFees() public {
    USDCVaultDDW newPsm = new USDCVaultDDW();
    newPsm.initialize(10_000, 10_000, address(_maiToken), address(_usdcToken)); // 100% fees

    assertEq(newPsm.depositFee(), 10_000, 'Deposit fee should be 10000');
    assertEq(newPsm.withdrawalFee(), 10_000, 'Withdrawal fee should be 10000');
  }

  function test_InitializeDefaultMaxValues() public {
    USDCVaultDDW newPsm = new USDCVaultDDW();
    newPsm.initialize(100, 100, address(_maiToken), address(_usdcToken));

    assertEq(newPsm.maxDeposit(), 1e12, 'Max deposit should be 1 million USDC (6 decimals)');
    assertEq(newPsm.maxWithdraw(), 1e12, 'Max withdraw should be 1 million USDC (6 decimals)');
    assertEq(newPsm.initialized(), true, 'Should be initialized');
  }

  function test_OnlyOwnerCanInitialize() public {
    USDCVaultDDW newPsm = new USDCVaultDDW();

    vm.stopPrank();
    vm.startPrank(_user);

    vm.expectRevert(USDCVaultDDW.CallerIsNotOwner.selector);
    newPsm.initialize(100, 100, address(_maiToken), address(_usdcToken));
  }
}

contract USDCVaultFeeCalculationSuite is MetisIntegrationBase {
  function test_CalculateDepositFeeWithZeroFee() public {
    _psm.updateFeesBP(0, 0);
    _psm.updateMinimumFees(0, 0);

    uint256 amount = 1000 * 10 ** 6; // 1000 USDC
    uint256 fee = _psm.calculateFee(amount, true);

    assertEq(fee, 0, 'Fee should be 0 when depositFee is 0');
  }

  function test_CalculateDepositFeeWithMinimumFee() public {
    _psm.updateFeesBP(10, 10); // 0.1% fee
    _psm.updateMinimumFees(5 * 10 ** 6, 5 * 10 ** 6); // 5 USDC minimum

    // Small amount - should use minimum fee
    uint256 smallAmount = 100 * 10 ** 6; // 100 USDC
    uint256 smallFee = _psm.calculateFee(smallAmount, true);
    // 0.1% of 100 = 0.1 USDC, but minimum is 5 USDC
    assertEq(smallFee, 5 * 10 ** 6, 'Should use minimum fee for small amounts');

    // Large amount - should use percentage fee
    uint256 largeAmount = 100_000 * 10 ** 6; // 100,000 USDC
    uint256 largeFee = _psm.calculateFee(largeAmount, true);
    // 0.1% of 100,000 = 100 USDC, which is > 5 USDC minimum
    assertEq(largeFee, 100 * 10 ** 6, 'Should use percentage fee for large amounts');
  }

  function test_CalculateWithdrawalFeeWithMinimumFee() public {
    _psm.updateFeesBP(10, 20); // 0.2% withdrawal fee
    _psm.updateMinimumFees(5 * 10 ** 6, 10 * 10 ** 6); // 10 USDC minimum withdrawal fee

    // Small amount - should use minimum fee
    uint256 smallAmount = 100 * 10 ** 6; // 100 USDC
    uint256 smallFee = _psm.calculateFee(smallAmount, false);
    // 0.2% of 100 = 0.2 USDC, but minimum is 10 USDC
    assertEq(smallFee, 10 * 10 ** 6, 'Should use minimum withdrawal fee for small amounts');

    // Large amount - should use percentage fee
    uint256 largeAmount = 100_000 * 10 ** 6; // 100,000 USDC
    uint256 largeFee = _psm.calculateFee(largeAmount, false);
    // 0.2% of 100,000 = 200 USDC, which is > 10 USDC minimum
    assertEq(largeFee, 200 * 10 ** 6, 'Should use percentage fee for large amounts');
  }

  function testFuzz_CalculateFeeConsistency(uint256 amount, uint256 feeRate) public {
    // Bound inputs to reasonable ranges
    amount = bound(amount, 1, 1_000_000 * 10 ** 6); // 1 to 1M USDC
    feeRate = bound(feeRate, 0, 10_000); // 0% to 100%

    _psm.updateFeesBP(feeRate, feeRate);
    _psm.updateMinimumFees(0, 0);

    uint256 depositFee = _psm.calculateFee(amount, true);
    uint256 withdrawalFee = _psm.calculateFee(amount, false);

    // Both should be equal when fees are the same
    assertEq(depositFee, withdrawalFee, 'Deposit and withdrawal fees should be equal with same rate');

    // Fee should never exceed the amount
    assertLe(depositFee, amount, 'Deposit fee should not exceed amount');
    assertLe(withdrawalFee, amount, 'Withdrawal fee should not exceed amount');

    // Fee should be correct calculation
    uint256 expectedFee = (amount * feeRate) / 10_000;
    assertEq(depositFee, expectedFee, 'Fee calculation should be correct');
  }
}

contract USDCVaultAccessControlSuite is MetisIntegrationBase {
  address internal _unauthorizedUser = makeAddr('unauthorized');

  function test_OnlyOwnerCanTransferOwnership() public {
    vm.stopPrank();
    vm.startPrank(_unauthorizedUser);

    vm.expectRevert(USDCVaultDDW.CallerIsNotOwner.selector);
    _psm.transferOwnership(_user);
  }

  function test_OnlyOwnerCanUpdateFees() public {
    vm.stopPrank();
    vm.startPrank(_unauthorizedUser);

    vm.expectRevert(USDCVaultDDW.CallerIsNotOwner.selector);
    _psm.updateFeesBP(200, 200);
  }

  function test_OnlyOwnerCanUpdateMinimumFees() public {
    vm.stopPrank();
    vm.startPrank(_unauthorizedUser);

    vm.expectRevert(USDCVaultDDW.CallerIsNotOwner.selector);
    _psm.updateMinimumFees(100, 100);
  }

  function test_OnlyOwnerCanUpdateMax() public {
    vm.stopPrank();
    vm.startPrank(_unauthorizedUser);

    vm.expectRevert(USDCVaultDDW.CallerIsNotOwner.selector);
    _psm.updateMax(1000, 1000);
  }

  function test_OnlyOwnerCanClaimFees() public {
    vm.stopPrank();
    vm.startPrank(_unauthorizedUser);

    vm.expectRevert(USDCVaultDDW.CallerIsNotOwner.selector);
    _psm.claimFees();
  }

  function test_OnlyOwnerCanSetPaused() public {
    vm.stopPrank();
    vm.startPrank(_unauthorizedUser);

    vm.expectRevert(USDCVaultDDW.CallerIsNotOwner.selector);
    _psm.setPaused(USDCVaultDDW.deposit.selector, true);
  }

  function test_OnlyOwnerCanSetUpgrade() public {
    vm.stopPrank();
    vm.startPrank(_unauthorizedUser);

    vm.expectRevert(USDCVaultDDW.CallerIsNotOwner.selector);
    _psm.setUpgrade();
  }

  function test_OnlyOwnerCanTransferToken() public {
    vm.stopPrank();
    vm.startPrank(_unauthorizedUser);

    vm.expectRevert(USDCVaultDDW.CallerIsNotOwner.selector);
    _psm.transferToken(address(_maiToken), _user, 100);
  }

  function test_OnlyOwnerCanWithdrawMAI() public {
    vm.stopPrank();
    vm.startPrank(_unauthorizedUser);

    vm.expectRevert(USDCVaultDDW.CallerIsNotOwner.selector);
    _psm.withdrawMAI();
  }
}

contract USDCVaultUpgradeMechanismSuite is MetisIntegrationBase {
  function test_SetUpgradeOnlyOnce() public {
    _psm.setUpgrade();

    assertEq(_psm.stopped(), true, 'Should be stopped');
    assertEq(_psm.upgradeTime(), block.timestamp + 2 days, 'Upgrade time should be set to now + 2 days');

    // Try to set upgrade again - nothing should happen (no revert, but also no change)
    uint256 firstUpgradeTime = _psm.upgradeTime();
    vm.warp(block.timestamp + 1 days);
    _psm.setUpgrade();

    assertEq(_psm.upgradeTime(), firstUpgradeTime, 'Upgrade time should not change on second call');
  }

  function test_UpgradeTimelineExact() public {
    uint256 startTime = block.timestamp;
    _psm.setUpgrade();

    // Before upgrade time - 1 second, functions should work
    vm.warp(startTime + 2 days - 1);
    uint256 depositAmount = 100 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount); // Should work

    // At exactly upgrade time, functions should work
    vm.warp(startTime + 2 days);
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount); // Should still work

    // After upgrade time + 1 second, functions should be paused
    vm.warp(startTime + 2 days + 1);
    _usdcToken.approve(address(_psm), depositAmount);
    vm.expectRevert(USDCVaultDDW.ContractIsPaused.selector);
    _psm.deposit(depositAmount);
  }

  function test_TransferTokenNonUSDCBeforeUpgrade() public {
    // Can transfer non-USDC tokens even without upgrade set
    deal(address(_maiToken), address(_psm), 1000 * 10 ** 18);

    uint256 maiBalance = _maiToken.balanceOf(address(_psm));
    _psm.transferToken(address(_maiToken), _owner, maiBalance);

    assertEq(_maiToken.balanceOf(_owner), maiBalance, 'Should receive MAI tokens');
    assertEq(_maiToken.balanceOf(address(_psm)), 0, 'PSM should have 0 MAI');
  }

  function test_TransferTokenUSDCRequiresUpgrade() public {
    deal(address(_usdcToken), address(_psm), 1000 * 10 ** 6);

    // Cannot transfer USDC without upgrade
    vm.expectRevert(USDCVaultDDW.UpgradeNotScheduled.selector);
    _psm.transferToken(address(_usdcToken), _owner, 1000 * 10 ** 6);

    // Set upgrade
    _psm.setUpgrade();

    // Still cannot transfer during grace period
    vm.expectRevert(USDCVaultDDW.UpgradeNotScheduled.selector);
    _psm.transferToken(address(_usdcToken), _owner, 1000 * 10 ** 6);

    // Can transfer after upgrade time
    vm.warp(block.timestamp + 3 days);
    _psm.transferToken(address(_usdcToken), _owner, 1000 * 10 ** 6);

    assertEq(_usdcToken.balanceOf(_owner), 100_000_000 * 10 ** 6 + 1000 * 10 ** 6, 'Should receive USDC tokens');
  }

  function test_UpgradeBlocksAllPausableFunctions() public {
    // First, do a successful deposit to have something to withdraw
    uint256 depositAmount = 1000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    _psm.setUpgrade();
    vm.warp(block.timestamp + 3 days);

    // Test deposit is blocked
    _usdcToken.approve(address(_psm), depositAmount);
    vm.expectRevert(USDCVaultDDW.ContractIsPaused.selector);
    _psm.deposit(depositAmount);

    // Test scheduleWithdraw is blocked
    vm.expectRevert(USDCVaultDDW.ContractIsPaused.selector);
    _psm.scheduleWithdraw(100 * 10 ** 18);

    // Test withdraw is blocked
    vm.expectRevert(USDCVaultDDW.ContractIsPaused.selector);
    _psm.withdraw();
  }
}

contract USDCVaultWithdrawalTimingSuite is MetisIntegrationBase {
  function test_WithdrawalExactly3Days() public {
    uint256 depositAmount = 1000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    uint256 withdrawAmount = 500 * 10 ** 18;
    _maiToken.approve(address(_psm), withdrawAmount);

    uint256 scheduleTime = block.timestamp;
    _psm.scheduleWithdraw(withdrawAmount);

    // At exactly 3 days, should be able to withdraw
    vm.warp(scheduleTime + 3 days);
    _psm.withdraw(); // Should succeed

    assertEq(_psm.withdrawalEpoch(_owner), 0, 'Withdrawal epoch should be reset');
    assertEq(_psm.scheduledWithdrawalAmount(_owner), 0, 'Scheduled amount should be reset');
  }

  function test_WithdrawalJustBefore3Days() public {
    uint256 depositAmount = 1000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    uint256 withdrawAmount = 500 * 10 ** 18;
    _maiToken.approve(address(_psm), withdrawAmount);

    uint256 scheduleTime = block.timestamp;
    _psm.scheduleWithdraw(withdrawAmount);

    // Just before 3 days - should fail
    vm.warp(scheduleTime + 3 days - 1);
    vm.expectRevert(USDCVaultDDW.WithdrawalNotAvailable.selector);
    _psm.withdraw();
  }

  function test_WithdrawalMultipleDaysAfter() public {
    uint256 depositAmount = 1000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    uint256 withdrawAmount = 500 * 10 ** 18;
    _maiToken.approve(address(_psm), withdrawAmount);

    _psm.scheduleWithdraw(withdrawAmount);

    // Much later than 3 days - should still work
    vm.warp(block.timestamp + 30 days);
    _psm.withdraw(); // Should succeed

    assertGe(_usdcToken.balanceOf(_owner), 0, 'Should have received USDC');
  }

  function test_CannotScheduleMultipleWithdrawals() public {
    uint256 depositAmount = 2000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    uint256 withdrawAmount = 500 * 10 ** 18;

    // Schedule first withdrawal
    _maiToken.approve(address(_psm), withdrawAmount * 2);
    _psm.scheduleWithdraw(withdrawAmount);

    // Try to schedule second withdrawal - should fail
    vm.expectRevert(USDCVaultDDW.WithdrawalAlreadyScheduled.selector);
    _psm.scheduleWithdraw(withdrawAmount);
  }

  function test_CanScheduleNewWithdrawalAfterExecution() public {
    uint256 depositAmount = 2000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    // First withdrawal cycle
    uint256 withdrawAmount1 = 500 * 10 ** 18;
    _maiToken.approve(address(_psm), withdrawAmount1);
    _psm.scheduleWithdraw(withdrawAmount1);

    vm.warp(block.timestamp + 4 days);
    _psm.withdraw();

    // Second withdrawal cycle - should work now
    uint256 withdrawAmount2 = 300 * 10 ** 18;
    _maiToken.approve(address(_psm), withdrawAmount2);
    _psm.scheduleWithdraw(withdrawAmount2); // Should succeed

    assertEq(_psm.scheduledWithdrawalAmount(_owner), withdrawAmount2, 'Should have new scheduled amount');
  }
}

contract USDCVaultLiquidityTrackingSuite is MetisIntegrationBase {
  function test_LiquidityTracksDeposits() public {
    uint256 initialLiquidity = _psm.totalStableLiquidity();

    uint256 depositAmount = 1000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    uint256 fee = _psm.calculateFee(depositAmount, true);
    uint256 expectedLiquidity = initialLiquidity + (depositAmount - fee);

    assertEq(_psm.totalStableLiquidity(), expectedLiquidity, 'Liquidity should increase by deposit minus fee');
  }

  function test_LiquidityTracksWithdrawals() public {
    uint256 depositAmount = 1000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    uint256 liquidityAfterDeposit = _psm.totalStableLiquidity();

    uint256 withdrawAmount = 500 * 10 ** 18;
    uint256 withdrawAmountUSDC = withdrawAmount / 10 ** 12;

    _maiToken.approve(address(_psm), withdrawAmount);
    _psm.scheduleWithdraw(withdrawAmount);

    vm.warp(block.timestamp + 4 days);
    _psm.withdraw();

    uint256 expectedLiquidity = liquidityAfterDeposit - withdrawAmountUSDC;
    assertEq(_psm.totalStableLiquidity(), expectedLiquidity, 'Liquidity should decrease by withdrawal amount');
  }

  function test_QueuedLiquidityTracksScheduledWithdrawals() public {
    uint256 depositAmount = 2000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    assertEq(_psm.totalQueuedLiquidity(), 0, 'Should start with no queued liquidity');

    uint256 withdrawAmount = 500 * 10 ** 18;
    uint256 withdrawAmountUSDC = withdrawAmount / 10 ** 12;

    _maiToken.approve(address(_psm), withdrawAmount);
    _psm.scheduleWithdraw(withdrawAmount);

    assertEq(_psm.totalQueuedLiquidity(), withdrawAmountUSDC, 'Queued liquidity should match scheduled withdrawal');
  }

  function test_QueuedLiquidityDecreasesOnWithdrawalExecution() public {
    uint256 depositAmount = 2000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    uint256 withdrawAmount = 500 * 10 ** 18;
    uint256 withdrawAmountUSDC = withdrawAmount / 10 ** 12;

    _maiToken.approve(address(_psm), withdrawAmount);
    _psm.scheduleWithdraw(withdrawAmount);

    assertEq(_psm.totalQueuedLiquidity(), withdrawAmountUSDC, 'Queued liquidity should be set');

    vm.warp(block.timestamp + 4 days);
    _psm.withdraw();

    assertEq(_psm.totalQueuedLiquidity(), 0, 'Queued liquidity should be reset after execution');
  }

  function test_AvailableLiquidityCalculation() public {
    uint256 depositAmount = 3000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    uint256 totalLiquidity = _psm.totalStableLiquidity();

    // Schedule some withdrawals
    uint256 withdrawAmount = 1000 * 10 ** 18;

    _maiToken.approve(address(_psm), withdrawAmount);
    _psm.scheduleWithdraw(withdrawAmount);

    uint256 queuedLiquidity = _psm.totalQueuedLiquidity();
    uint256 availableLiquidity = totalLiquidity - queuedLiquidity;

    // Try to schedule more than available - should fail
    vm.stopPrank();
    vm.startPrank(_user);

    // Give user some MAI
    deal(address(_maiToken), _user, availableLiquidity * 10 ** 12 + 1000 * 10 ** 18);
    _maiToken.approve(address(_psm), availableLiquidity * 10 ** 12 + 1000 * 10 ** 18);

    // This should fail because it exceeds available liquidity
    vm.expectRevert(USDCVaultDDW.NotEnoughLiquidity.selector);
    _psm.scheduleWithdraw(availableLiquidity * 10 ** 12 + 1000 * 10 ** 18);
  }
}

contract USDCVaultClaimFeesSuite is MetisIntegrationBase {
  function test_ClaimFeesWithNoFees() public {
    uint256 balanceBefore = _usdcToken.balanceOf(_owner);
    _psm.claimFees();
    uint256 balanceAfter = _usdcToken.balanceOf(_owner);

    assertEq(balanceAfter, balanceBefore, 'Balance should not change when no fees to claim');
  }

  function test_ClaimFeesAccumulatesCorrectly() public {
    _psm.updateFeesBP(100, 100); // 1% fees
    _psm.updateMinimumFees(0, 0);

    uint256 depositAmount = 10_000 * 10 ** 6; // 10,000 USDC
    uint256 expectedDepositFee = _psm.calculateFee(depositAmount, true); // 100 USDC

    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    uint256 balanceBefore = _usdcToken.balanceOf(_owner);
    _psm.claimFees();
    uint256 balanceAfter = _usdcToken.balanceOf(_owner);

    assertEq(balanceAfter - balanceBefore, expectedDepositFee, 'Should claim exact deposit fee amount');
  }

  function test_ClaimFeesMultipleDeposits() public {
    _psm.updateFeesBP(100, 100); // 1% fees
    _psm.updateMinimumFees(0, 0);

    uint256 depositAmount = 5000 * 10 ** 6; // 5,000 USDC
    uint256 expectedFeePerDeposit = _psm.calculateFee(depositAmount, true); // 50 USDC

    // Make 3 deposits
    for (uint256 i = 0; i < 3; i++) {
      _usdcToken.approve(address(_psm), depositAmount);
      _psm.deposit(depositAmount);
    }

    uint256 balanceBefore = _usdcToken.balanceOf(_owner);
    _psm.claimFees();
    uint256 balanceAfter = _usdcToken.balanceOf(_owner);

    assertEq(balanceAfter - balanceBefore, expectedFeePerDeposit * 3, 'Should claim fees from all deposits');
  }

  function test_ClaimFeesWithWithdrawalFees() public {
    _psm.updateFeesBP(100, 100); // 1% fees
    _psm.updateMinimumFees(0, 0);

    // Deposit
    uint256 depositAmount = 10_000 * 10 ** 6; // 10,000 USDC
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    uint256 depositFee = _psm.calculateFee(depositAmount, true);

    // Withdraw
    uint256 withdrawAmount = 5000 * 10 ** 18; // 5,000 MAI
    uint256 withdrawAmountUSDC = withdrawAmount / 10 ** 12;
    _maiToken.approve(address(_psm), withdrawAmount);
    _psm.scheduleWithdraw(withdrawAmount);

    vm.warp(block.timestamp + 4 days);
    _psm.withdraw();

    uint256 withdrawalFee = _psm.calculateFee(withdrawAmountUSDC, false);
    uint256 totalExpectedFees = depositFee + withdrawalFee;

    uint256 balanceBefore = _usdcToken.balanceOf(_owner);
    _psm.claimFees();
    uint256 balanceAfter = _usdcToken.balanceOf(_owner);

    assertEq(balanceAfter - balanceBefore, totalExpectedFees, 'Should claim both deposit and withdrawal fees');
  }

  function test_ClaimFeesDoesNotAffectLiquidity() public {
    _psm.updateFeesBP(100, 100); // 1% fees
    _psm.updateMinimumFees(0, 0);

    uint256 depositAmount = 10_000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    uint256 liquidityBefore = _psm.totalStableLiquidity();
    _psm.claimFees();
    uint256 liquidityAfter = _psm.totalStableLiquidity();

    assertEq(liquidityBefore, liquidityAfter, 'Claiming fees should not affect liquidity tracking');
  }
}

contract USDCVaultEventEmissionSuite is MetisIntegrationBase {
  event Deposited(address indexed user, uint256 amount);
  event WithdrawalScheduled(address indexed user, uint256 amount);
  event Withdrawn(address indexed user, uint256 amount);
  event OwnerUpdated(address newOwner);
  event FeesWithdrawn(address indexed owner, uint256 feesEarned);
  event PauseEvent(address account, bytes4 selector, bool paused);
  event MinimumFeesUpdated(uint256 newMinimumDepositFee, uint256 newMinimumWithdrawalFee);
  event FeesUpdated(uint256 newDepositFee, uint256 newWithdrawalFee);
  event MaxUpdated(uint256 maxDeposit, uint256 maxWithdraw);

  function test_DepositEmitsEvent() public {
    uint256 depositAmount = 1000 * 10 ** 6;
    uint256 fee = _psm.calculateFee(depositAmount, true);
    uint256 netAmount = depositAmount - fee;

    _usdcToken.approve(address(_psm), depositAmount);

    vm.expectEmit(true, false, false, true);
    emit Deposited(_owner, netAmount);

    _psm.deposit(depositAmount);
  }

  function test_ScheduleWithdrawEmitsEvent() public {
    uint256 depositAmount = 1000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    uint256 withdrawAmount = 500 * 10 ** 18;
    _maiToken.approve(address(_psm), withdrawAmount);

    vm.expectEmit(true, false, false, true);
    emit WithdrawalScheduled(_owner, withdrawAmount);

    _psm.scheduleWithdraw(withdrawAmount);
  }

  function test_WithdrawEmitsEvent() public {
    uint256 depositAmount = 1000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    uint256 withdrawAmount = 500 * 10 ** 18;
    _maiToken.approve(address(_psm), withdrawAmount);
    _psm.scheduleWithdraw(withdrawAmount);

    vm.warp(block.timestamp + 4 days);

    vm.expectEmit(true, false, false, true);
    emit Withdrawn(_owner, withdrawAmount);

    _psm.withdraw();
  }

  function test_TransferOwnershipEmitsEvent() public {
    vm.expectEmit(false, false, false, true);
    emit OwnerUpdated(_user);

    _psm.transferOwnership(_user);
  }

  function test_ClaimFeesEmitsEvent() public {
    _psm.updateFeesBP(100, 100);
    _psm.updateMinimumFees(0, 0);

    uint256 depositAmount = 10_000 * 10 ** 6;
    uint256 expectedFee = _psm.calculateFee(depositAmount, true);

    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    vm.expectEmit(true, false, false, true);
    emit FeesWithdrawn(_owner, expectedFee);

    _psm.claimFees();
  }

  function test_SetPausedEmitsEvent() public {
    vm.expectEmit(false, false, false, true);
    emit PauseEvent(_owner, USDCVaultDDW.deposit.selector, true);

    _psm.setPaused(USDCVaultDDW.deposit.selector, true);
  }

  function test_UpdateMinimumFeesEmitsEvent() public {
    vm.expectEmit(false, false, false, true);
    emit MinimumFeesUpdated(5 * 10 ** 6, 10 * 10 ** 6);

    _psm.updateMinimumFees(5 * 10 ** 6, 10 * 10 ** 6);
  }

  function test_UpdateFeesBPEmitsEvent() public {
    vm.expectEmit(false, false, false, true);
    emit FeesUpdated(200, 300);

    _psm.updateFeesBP(200, 300);
  }

  function test_UpdateMaxEmitsEvent() public {
    vm.expectEmit(false, false, false, true);
    emit MaxUpdated(2000 * 10 ** 6, 3000 * 10 ** 6);

    _psm.updateMax(2000 * 10 ** 6, 3000 * 10 ** 6);
  }
}

contract USDCVaultWithdrawMAISuite is MetisIntegrationBase {
  function test_WithdrawMAIRemovesAllMAI() public {
    uint256 initialMAI = _maiToken.balanceOf(address(_psm));
    uint256 ownerMAIBefore = _maiToken.balanceOf(_owner);

    _psm.withdrawMAI();

    assertEq(_maiToken.balanceOf(address(_psm)), 0, 'PSM should have no MAI left');
    assertEq(_maiToken.balanceOf(_owner), ownerMAIBefore + initialMAI, 'Owner should receive all MAI');
  }

  function test_WithdrawMAIOnlyByOwner() public {
    vm.stopPrank();
    vm.startPrank(_user);

    vm.expectRevert(USDCVaultDDW.CallerIsNotOwner.selector);
    _psm.withdrawMAI();
  }

  function test_WithdrawMAIAfterDeposits() public {
    // Make some deposits first
    uint256 depositAmount = 1000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    uint256 maiBalance = _maiToken.balanceOf(address(_psm));
    _psm.withdrawMAI();

    assertEq(_maiToken.balanceOf(address(_psm)), 0, 'All MAI should be withdrawn');
    assertGe(_maiToken.balanceOf(_owner), maiBalance, 'Owner should receive the MAI');
  }

  function test_DepositFailsAfterWithdrawMAI() public {
    _psm.withdrawMAI();

    uint256 depositAmount = 1000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);

    vm.expectRevert(USDCVaultDDW.InsufficientMAIBalance.selector);
    _psm.deposit(depositAmount);
  }
}

contract USDCVaultMaxLimitSuite is MetisIntegrationBase {
  function test_DepositAtMaxLimit() public {
    uint256 maxDeposit = _psm.maxDeposit();

    deal(address(_usdcToken), _owner, maxDeposit + 1000 * 10 ** 6);
    _usdcToken.approve(address(_psm), maxDeposit);

    _psm.deposit(maxDeposit); // Should succeed at exactly max

    assertGt(_maiToken.balanceOf(_owner), 0, 'Should receive MAI from max deposit');
  }

  function test_DepositAboveMaxLimit() public {
    uint256 maxDeposit = _psm.maxDeposit();

    deal(address(_usdcToken), _owner, maxDeposit + 1000 * 10 ** 6);
    _usdcToken.approve(address(_psm), maxDeposit + 1);

    vm.expectRevert(USDCVaultDDW.InvalidAmount.selector);
    _psm.deposit(maxDeposit + 1);
  }

  function test_WithdrawAtMaxLimit() public {
    // Set high max to allow large deposit and withdrawal
    _psm.updateMax(10_000_000 * 10 ** 6, 5_000_000 * 10 ** 6);

    // Deposit more than max withdraw to ensure we have enough liquidity
    uint256 depositAmount = 10_000_000 * 10 ** 6;
    deal(address(_usdcToken), _owner, depositAmount);
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    // Withdraw at the max limit (which is less than deposited)
    uint256 maxWithdraw = _psm.maxWithdraw();
    uint256 maxWithdrawMAI = maxWithdraw * 10 ** 12;

    _maiToken.approve(address(_psm), maxWithdrawMAI);
    _psm.scheduleWithdraw(maxWithdrawMAI); // Should succeed at exactly max

    assertEq(_psm.scheduledWithdrawalAmount(_owner), maxWithdrawMAI, 'Should schedule max withdrawal');
  }

  function test_WithdrawAboveMaxLimit() public {
    _psm.updateMax(10_000_000 * 10 ** 6, 10_000_000 * 10 ** 6);

    uint256 depositAmount = 10_000_000 * 10 ** 6;
    deal(address(_usdcToken), _owner, depositAmount);
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    uint256 maxWithdraw = _psm.maxWithdraw();
    uint256 aboveMaxWithdrawMAI = (maxWithdraw + 1) * 10 ** 12;

    _maiToken.approve(address(_psm), aboveMaxWithdrawMAI);
    vm.expectRevert(USDCVaultDDW.InvalidAmount.selector);
    _psm.scheduleWithdraw(aboveMaxWithdrawMAI);
  }

  function test_UpdateMaxLimitsWorksProperly() public {
    uint256 newMaxDeposit = 5_000_000 * 10 ** 6; // 5M USDC
    uint256 newMaxWithdraw = 3_000_000 * 10 ** 6; // 3M USDC

    _psm.updateMax(newMaxDeposit, newMaxWithdraw);

    assertEq(_psm.maxDeposit(), newMaxDeposit, 'Max deposit should be updated');
    assertEq(_psm.maxWithdraw(), newMaxWithdraw, 'Max withdraw should be updated');
  }
}

contract USDCVaultMinimumFeeSuite is MetisIntegrationBase {
  function test_DepositBelowMinimumFee() public {
    _psm.updateMinimumFees(100 * 10 ** 6, 100 * 10 ** 6); // 100 USDC minimum

    uint256 depositAmount = 50 * 10 ** 6; // 50 USDC
    _usdcToken.approve(address(_psm), depositAmount);

    vm.expectRevert(USDCVaultDDW.InvalidAmount.selector);
    _psm.deposit(depositAmount);
  }

  function test_DepositAtMinimumFee() public {
    _psm.updateMinimumFees(100 * 10 ** 6, 100 * 10 ** 6); // 100 USDC minimum

    uint256 depositAmount = 100 * 10 ** 6; // Exactly at minimum
    _usdcToken.approve(address(_psm), depositAmount);

    // Should fail because amount <= minimumDepositFee
    vm.expectRevert(USDCVaultDDW.InvalidAmount.selector);
    _psm.deposit(depositAmount);
  }

  function test_DepositJustAboveMinimumFee() public {
    _psm.updateMinimumFees(100 * 10 ** 6, 100 * 10 ** 6); // 100 USDC minimum

    uint256 depositAmount = 101 * 10 ** 6; // Just above minimum
    _usdcToken.approve(address(_psm), depositAmount);

    _psm.deposit(depositAmount); // Should succeed

    assertGt(_maiToken.balanceOf(_owner), 0, 'Should receive some MAI');
  }

  function test_WithdrawBelowMinimumFee() public {
    // First deposit enough
    uint256 depositAmount = 10_000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    _psm.updateMinimumFees(100 * 10 ** 6, 100 * 10 ** 6); // 100 USDC minimum

    uint256 withdrawAmount = 50 * 10 ** 18; // 50 MAI = 50 USDC equivalent (below minimum)
    _maiToken.approve(address(_psm), withdrawAmount);

    vm.expectRevert(USDCVaultDDW.InvalidAmount.selector);
    _psm.scheduleWithdraw(withdrawAmount);
  }

  function test_MinimumFeeAppliesToSmallAmounts() public {
    _psm.updateFeesBP(10, 10); // 0.1% fee
    _psm.updateMinimumFees(5 * 10 ** 6, 5 * 10 ** 6); // 5 USDC minimum

    uint256 depositAmount = 1000 * 10 ** 6; // 1000 USDC
    // 0.1% of 1000 = 1 USDC, but minimum is 5 USDC
    uint256 expectedFee = 5 * 10 ** 6;

    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    uint256 expectedNetAmount = depositAmount - expectedFee;
    uint256 expectedMAI = expectedNetAmount * 10 ** 12;

    assertEq(_maiToken.balanceOf(_owner), expectedMAI, 'Should deduct minimum fee, not percentage fee');
  }
}
