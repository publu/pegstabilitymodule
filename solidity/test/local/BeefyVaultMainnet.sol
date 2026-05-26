// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {Test} from 'forge-std/Test.sol';
import {IBeefy} from '../../interfaces/IBeefy.sol';
import {BeefyVaultPSMV2} from 'contracts/BeefyVaultPSM/V2.sol';
import 'forge-std/console.sol';
import {MainnetLocalBase} from './MainnetLocalBase.sol';
import {StdCheats} from 'forge-std/StdCheats.sol';

contract PsmMainnetConstructor is MainnetLocalBase {
  function test_OwnerSet() public {
    BeefyVaultPSMV2 newPsm = new BeefyVaultPSMV2();
    newPsm.initialize(address(_mooToken), 100, 100, address(_maiToken));

    assertEq(newPsm.owner(), address(_owner));
  }

  function test_TokenSet() public {
    BeefyVaultPSMV2 newPsm = new BeefyVaultPSMV2();
    newPsm.initialize(address(_mooToken), 100, 100, address(_maiToken));

    assertEq(address(newPsm.gem()), address(_mooToken));
  }

  function test_MAIAddressSet() public {
    BeefyVaultPSMV2 newPsm = new BeefyVaultPSMV2();
    newPsm.initialize(address(_mooToken), 100, 100, address(_maiToken));

    assertEq(newPsm.MAI_ADDRESS(), address(_maiToken));
  }

  function test_MAIAddressCannotBeZero() public {
    BeefyVaultPSMV2 newPsm = new BeefyVaultPSMV2();

    vm.expectRevert(BeefyVaultPSMV2.MAIAddressCannotBeZero.selector);
    newPsm.initialize(address(_mooToken), 100, 100, address(0));
  }

  function test_UnderlyingSet() public {
    BeefyVaultPSMV2 newPsm = new BeefyVaultPSMV2();
    newPsm.initialize(address(_mooToken), 100, 100, address(_maiToken));
    assertEq(address(newPsm.underlying()), address(_usdcToken));
  }

  function test_MinimumReservesDefaultsToZero() public {
    BeefyVaultPSMV2 newPsm = new BeefyVaultPSMV2();
    newPsm.initialize(address(_mooToken), 100, 100, address(_maiToken));

    assertEq(newPsm.minimumReserves(), 0);
  }

  function test_Initialized() public {
    BeefyVaultPSMV2 newPsm = new BeefyVaultPSMV2();
    newPsm.initialize(address(_mooToken), 100, 100, address(_maiToken));

    assertEq(newPsm.initialized(), true);
    vm.expectRevert(BeefyVaultPSMV2.AlreadyInitialized.selector);
    newPsm.initialize(address(_mooToken), 100, 100, address(_maiToken));
  }
}

contract PsmMainnetMinimumReservesConfig is MainnetLocalBase {
  event MinimumReservesUpdated(uint256 _oldMinimumReserves, uint256 _newMinimumReserves);

  function test_SetMinimumReservesOnlyOwner() public {
    vm.stopPrank();
    vm.startPrank(_user);

    vm.expectRevert(BeefyVaultPSMV2.CallerIsNotOwner.selector);
    _psm.setMinimumReserves(1000 * 10 ** 6);
  }

  function test_SetMinimumReservesEmitsEvent() public {
    vm.expectEmit(true, true, true, true);
    emit MinimumReservesUpdated(0, 1000 * 10 ** 6);

    _psm.setMinimumReserves(1000 * 10 ** 6);
  }

  function test_SetMinimumReservesToZero() public {
    _psm.setMinimumReserves(1000 * 10 ** 6);
    assertEq(_psm.minimumReserves(), 1000 * 10 ** 6);

    _psm.setMinimumReserves(0);
    assertEq(_psm.minimumReserves(), 0);
  }

  function test_SetMinimumReservesUpdatesValue() public {
    _psm.setMinimumReserves(500 * 10 ** 6);
    assertEq(_psm.minimumReserves(), 500 * 10 ** 6);

    _psm.setMinimumReserves(1000 * 10 ** 6);
    assertEq(_psm.minimumReserves(), 1000 * 10 ** 6);
  }

  function testFuzz_SetMinimumReserves(
    uint256 _amount
  ) public {
    _amount = bound(_amount, 0, 1_000_000_000 * 10 ** 6);

    _psm.setMinimumReserves(_amount);
    assertEq(_psm.minimumReserves(), _amount);
  }
}

contract PsmMainnetMinimumReservesEnforcement is MainnetLocalBase {
  function test_WithdrawBlockedByMinimumReserves() public {
    // Deposit 1000 USDC
    uint256 depositAmount = 1000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    // Set minimum reserves to 900 USDC
    _psm.setMinimumReserves(900 * 10 ** 6);

    // Calculate available: totalLiquidity (~990 after 1% fee) - 900 = ~90 USDC
    // Try to withdraw 100 USDC worth of MAI (more than available)
    uint256 tooMuchMAI = 100 * 10 ** 18;

    _maiToken.approve(address(_psm), tooMuchMAI);
    vm.expectRevert(BeefyVaultPSMV2.MinimumReservesBreached.selector);
    _psm.scheduleWithdraw(tooMuchMAI);
  }

  function test_WithdrawAllowedUpToAvailable() public {
    // Deposit 1000 USDC
    uint256 depositAmount = 1000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    // Set minimum reserves to 500 USDC
    _psm.setMinimumReserves(500 * 10 ** 6);

    // Calculate available
    uint256 available = _psm.availableForWithdrawal();
    console.log('Available for withdrawal:', available);

    // Withdraw exactly the available amount
    uint256 withdrawAmountMAI = available * 10 ** 12;

    _maiToken.approve(address(_psm), withdrawAmountMAI);
    _psm.scheduleWithdraw(withdrawAmountMAI); // Should succeed

    assertEq(_psm.scheduledWithdrawalAmount(_owner), withdrawAmountMAI);
  }

  function test_DepositUnaffectedByMinimumReserves() public {
    // Set high minimum reserves before any deposits
    _psm.setMinimumReserves(1_000_000 * 10 ** 6); // 1M USDC

    // Deposits should still work
    uint256 depositAmount = 1000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);

    uint256 maiBefore = _maiToken.balanceOf(_owner);
    _psm.deposit(depositAmount);
    uint256 maiAfter = _maiToken.balanceOf(_owner);

    assertGt(maiAfter, maiBefore, 'User should have received MAI');
  }

  function test_ClaimFeesUnaffectedByMinimumReserves() public {
    // Deposit and generate some fees
    uint256 depositAmount = 10_000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    // Set high minimum reserves
    _psm.setMinimumReserves(1_000_000 * 10 ** 6);

    // claimFees should still work even with high minimum reserves
    // The key test is that claimFees doesn't revert due to minimum reserves
    uint256 balanceBefore = _usdcToken.balanceOf(_owner);
    _psm.claimFees();
    uint256 balanceAfter = _usdcToken.balanceOf(_owner);

    // Fees may or may not have been claimed depending on yield accumulation
    // The important thing is it doesn't revert
    console.log('Fees claimed:', balanceAfter - balanceBefore);
  }

  function test_QueuedWithdrawalsAccountedCorrectly() public {
    // Deposit 2000 USDC
    uint256 depositAmount = 2000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    // Set minimum reserves to 500 USDC
    _psm.setMinimumReserves(500 * 10 ** 6);

    // First withdrawal of 1000 MAI (1000 USDC equivalent)
    uint256 firstWithdrawMAI = 1000 * 10 ** 18;
    _maiToken.approve(address(_psm), firstWithdrawMAI);
    _psm.scheduleWithdraw(firstWithdrawMAI);

    // Check available has decreased
    uint256 availableAfterFirst = _psm.availableForWithdrawal();
    console.log('Available after first schedule:', availableAfterFirst);

    // totalLiquidity (~1980 after fee) - queued (1000) - min (500) = ~480 USDC
    assertApproxEqAbs(availableAfterFirst, 480 * 10 ** 6, 30 * 10 ** 6, 'Available should be ~480 USDC');

    // Second user tries to withdraw too much
    vm.stopPrank();
    vm.startPrank(_user);
    _dealToken(address(_maiToken), _user, 600 * 10 ** 18);
    _maiToken.approve(address(_psm), 600 * 10 ** 18);

    vm.expectRevert(BeefyVaultPSMV2.MinimumReservesBreached.selector);
    _psm.scheduleWithdraw(600 * 10 ** 18);
  }

  function test_ScheduledWithdrawalsCompleteEvenAfterReservesIncrease() public {
    // Deposit 2000 USDC
    uint256 depositAmount = 2000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    // Schedule withdrawal before setting minimum reserves
    uint256 withdrawMAI = 1000 * 10 ** 18;
    _maiToken.approve(address(_psm), withdrawMAI);
    _psm.scheduleWithdraw(withdrawMAI);

    // Now increase minimum reserves to a very high value
    _psm.setMinimumReserves(1_000_000 * 10 ** 6);

    // Warp time to execute withdrawal
    vm.warp(block.timestamp + 4 days);

    // Withdrawal should still complete (was scheduled before reserves increased)
    uint256 usdcBefore = _usdcToken.balanceOf(_owner);
    _psm.withdraw();
    uint256 usdcAfter = _usdcToken.balanceOf(_owner);

    assertGt(usdcAfter, usdcBefore, 'User should have received USDC');
  }

  function testFuzz_MinimumReservesEnforcement(
    uint256 depositAmount,
    uint256 minReserves,
    uint256 withdrawAmount
  ) public {
    // Bound inputs to reasonable ranges
    depositAmount = bound(depositAmount, 10 * 10 ** 6, 100_000 * 10 ** 6);
    minReserves = bound(minReserves, 0, depositAmount);
    withdrawAmount = bound(withdrawAmount, 1 * 10 ** 18, depositAmount * 10 ** 12);

    // Deposit
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    // Set minimum reserves
    _psm.setMinimumReserves(minReserves);

    uint256 available = _psm.availableForWithdrawal();
    uint256 withdrawInUnderlying = withdrawAmount / 10 ** 12;

    // Deal MAI to owner so they have enough for the withdrawal attempt
    // (deposit may give less MAI than withdrawAmount due to fees)
    // Note: _dealToken stops the prank, so we need to restart it
    _dealToken(address(_maiToken), _owner, withdrawAmount);
    vm.startPrank(_owner);
    _maiToken.approve(address(_psm), withdrawAmount);

    uint256 _feeCheck = _psm.calculateFee(withdrawInUnderlying, false);
    if (withdrawInUnderlying <= _feeCheck) {
      // Dust amount: USDC equivalent consumed by fee floor
      vm.expectRevert(BeefyVaultPSMV2.InvalidAmountAfterFee.selector);
      _psm.scheduleWithdraw(withdrawAmount);
    } else if (withdrawInUnderlying > available) {
      // Should revert
      vm.expectRevert(BeefyVaultPSMV2.MinimumReservesBreached.selector);
      _psm.scheduleWithdraw(withdrawAmount);
    } else if (withdrawAmount < _psm.minimumWithdrawalFee()) {
      // Should revert for invalid amount
      vm.expectRevert(BeefyVaultPSMV2.InvalidAmount.selector);
      _psm.scheduleWithdraw(withdrawAmount);
    } else {
      // Should succeed
      _psm.scheduleWithdraw(withdrawAmount);
      assertEq(_psm.scheduledWithdrawalAmount(_owner), withdrawAmount);
    }
  }
}

contract PsmMainnetAvailableForWithdrawalView is MainnetLocalBase {
  function test_AvailableForWithdrawalInitiallyZero() public {
    assertEq(_psm.availableForWithdrawal(), 0);
  }

  function test_AvailableForWithdrawalAfterDeposit() public {
    uint256 depositAmount = 1000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    uint256 fee = _psm.calculateFee(depositAmount, true);
    uint256 expectedAvailable = depositAmount - fee;

    assertEq(_psm.availableForWithdrawal(), expectedAvailable);
  }

  function test_AvailableForWithdrawalWithMinimumReserves() public {
    uint256 depositAmount = 1000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    _psm.setMinimumReserves(300 * 10 ** 6);

    uint256 fee = _psm.calculateFee(depositAmount, true);
    uint256 expectedAvailable = depositAmount - fee - 300 * 10 ** 6;

    assertEq(_psm.availableForWithdrawal(), expectedAvailable);
  }

  function test_AvailableForWithdrawalReturnsZeroWhenBelowMinimum() public {
    uint256 depositAmount = 100 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    _psm.setMinimumReserves(500 * 10 ** 6);

    assertEq(_psm.availableForWithdrawal(), 0);
  }

  function test_AvailableForWithdrawalInMAIDecimals() public {
    uint256 depositAmount = 1000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    uint256 availableUSDC = _psm.availableForWithdrawal();
    uint256 availableMAI = _psm.availableForWithdrawalInMAI();

    assertEq(availableMAI, availableUSDC * 10 ** 12);
  }

  function test_AvailableForWithdrawalWithQueuedLiquidity() public {
    uint256 depositAmount = 2000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    // Schedule a withdrawal
    uint256 withdrawMAI = 500 * 10 ** 18;
    _maiToken.approve(address(_psm), withdrawMAI);
    _psm.scheduleWithdraw(withdrawMAI);

    // Set minimum reserves
    _psm.setMinimumReserves(300 * 10 ** 6);

    // Available = totalStable - queued - minReserves
    uint256 fee = _psm.calculateFee(depositAmount, true);
    uint256 totalStable = depositAmount - fee;
    uint256 queued = 500 * 10 ** 6;
    uint256 minReserves = 300 * 10 ** 6;
    uint256 expectedAvailable = totalStable - queued - minReserves;

    assertEq(_psm.availableForWithdrawal(), expectedAvailable);
  }

  function testFuzz_AvailableForWithdrawal(
    uint256 depositAmount,
    uint256 minReserves,
    uint256 queueAmount
  ) public {
    depositAmount = bound(depositAmount, 10 * 10 ** 6, 100_000 * 10 ** 6);

    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    uint256 fee = _psm.calculateFee(depositAmount, true);
    uint256 totalStable = depositAmount - fee;

    // Only queue if we have liquidity AND the underlying-decimal queueAmount
    // strictly exceeds the contract's minimumWithdrawalFee (also in 6 decimals).
    // The previous check incorrectly compared queueMAI (18-decimal) against
    // minimumWithdrawalFee (6-decimal), letting tiny amounts through that the
    // V2 contract then rejects with InvalidAmountAfterFee at scheduleWithdraw:184.
    queueAmount = bound(queueAmount, 0, totalStable / 2);
    uint256 minWithdrawal = _psm.minimumWithdrawalFee(); // 6 decimals
    if (queueAmount > minWithdrawal) {
      uint256 queueMAI = queueAmount * 10 ** 12;
      _maiToken.approve(address(_psm), queueMAI);
      _psm.scheduleWithdraw(queueMAI);
    }

    uint256 queued = _psm.totalQueuedLiquidity();
    minReserves = bound(minReserves, 0, totalStable);
    _psm.setMinimumReserves(minReserves);

    uint256 available = _psm.availableForWithdrawal();
    uint256 liquidity = totalStable - queued;

    if (liquidity <= minReserves) {
      assertEq(available, 0, 'Available should be 0 when liquidity <= minReserves');
    } else {
      // Mirror BeefyVaultPSMV2.availableForWithdrawal() fee-floor guard:
      // when the post-reserve liquidity wouldn't survive the withdrawal fee
      // (e.g. dust amounts where minimumWithdrawalFee > _available), the view
      // returns 0 by design instead of returning a value users can't actually
      // withdraw.
      uint256 expectedAvailable = liquidity - minReserves;
      uint256 expectedFee = _psm.calculateFee(expectedAvailable, false);
      if (expectedAvailable <= expectedFee) {
        assertEq(available, 0, 'Available should be 0 when post-reserve amount is consumed by fee floor');
      } else {
        assertEq(available, expectedAvailable, 'Available calculation incorrect');
      }
    }
  }
}

contract PsmMainnetAdminSuite is MainnetLocalBase {
  function test_TransferOwnership() public {
    vm.expectRevert(BeefyVaultPSMV2.NewOwnerCannotBeZeroAddress.selector);
    _psm.transferOwnership(address(0x0));

    _psm.transferOwnership(address(_user));
    assertEq(_psm.owner(), address(_owner));
    assertEq(_psm.pendingOwner(), address(_user));

    vm.stopPrank();
    vm.prank(_user);
    _psm.acceptOwnership();
    assertEq(_psm.owner(), address(_user));
    assertEq(_psm.pendingOwner(), address(0));

    vm.expectRevert(BeefyVaultPSMV2.CallerIsNotOwner.selector);
    _psm.transferOwnership(address(0));
  }

  function test_PendingOwnerCannotActBeforeAccepting() public {
    _psm.transferOwnership(address(_user));

    vm.stopPrank();
    vm.prank(_user);
    vm.expectRevert(BeefyVaultPSMV2.CallerIsNotOwner.selector);
    _psm.setPaused(BeefyVaultPSMV2.deposit.selector, true);
  }

  function test_AcceptOwnershipRejectsNonPendingOwner() public {
    _psm.transferOwnership(address(_user));

    address notPending = makeAddr('notPending');
    vm.stopPrank();
    vm.prank(notPending);
    vm.expectRevert(BeefyVaultPSMV2.CallerIsNotPendingOwner.selector);
    _psm.acceptOwnership();
  }

  function test_Pausing() public {
    _psm.setPaused(BeefyVaultPSMV2.deposit.selector, true);

    _usdcToken.approve(address(_psm), 1000 * 10 ** 6);
    vm.expectRevert(BeefyVaultPSMV2.ContractIsPaused.selector);
    _psm.deposit(1000 * 10 ** 6);
  }

  function test_UpdateFeesBP() public {
    assertEq(_psm.depositFee(), 100);
    assertEq(_psm.withdrawalFee(), 100);

    _psm.updateFeesBP(200, 200);

    assertEq(_psm.depositFee(), 200);
    assertEq(_psm.withdrawalFee(), 200);
  }

  function test_UpdateMinimumFees() public {
    _psm.updateMinimumFees(200, 200);
    assertEq(_psm.minimumDepositFee(), 200);
    assertEq(_psm.minimumWithdrawalFee(), 200);
  }

  function test_UpdateMax() public {
    _psm.updateMax(200, 3000);
    assertEq(_psm.maxDeposit(), 200);
    assertEq(_psm.maxWithdraw(), 3000);
  }
}

contract PsmMainnetDepositWithdrawCycle is MainnetLocalBase {
  function test_FullDepositWithdrawCycleWithMinReserves() public {
    // Set minimum reserves
    _psm.setMinimumReserves(100 * 10 ** 6);

    // Deposit 1000 USDC
    uint256 depositAmount = 1000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);

    uint256 maiBalanceBefore = _maiToken.balanceOf(_owner);
    _psm.deposit(depositAmount);
    uint256 maiBalanceAfter = _maiToken.balanceOf(_owner);

    uint256 maiReceived = maiBalanceAfter - maiBalanceBefore;
    console.log('MAI received from deposit:', maiReceived);

    // Schedule withdrawal (should respect minimum reserves)
    uint256 available = _psm.availableForWithdrawal();
    console.log('Available for withdrawal:', available);

    uint256 withdrawMAI = available * 10 ** 12;
    _maiToken.approve(address(_psm), withdrawMAI);
    _psm.scheduleWithdraw(withdrawMAI);

    // Verify queued correctly
    assertEq(_psm.scheduledWithdrawalAmount(_owner), withdrawMAI);
    assertEq(_psm.totalQueuedLiquidity(), available);

    // Warp time
    vm.warp(block.timestamp + 4 days);

    // Execute withdrawal
    uint256 usdcBefore = _usdcToken.balanceOf(_owner);
    _psm.withdraw();
    uint256 usdcAfter = _usdcToken.balanceOf(_owner);

    console.log('USDC received from withdrawal:', usdcAfter - usdcBefore);
    assertGt(usdcAfter, usdcBefore, 'Should have received USDC');

    // Verify remaining liquidity respects minimum reserves
    uint256 remainingLiquidity = _psm.totalStableLiquidity() - _psm.totalQueuedLiquidity();
    console.log('Remaining liquidity:', remainingLiquidity);
    assertGe(remainingLiquidity, _psm.minimumReserves(), 'Remaining should be >= minimum reserves');
  }
}
