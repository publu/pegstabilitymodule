// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {StdCheats} from 'forge-std/StdCheats.sol';
import {Test} from 'forge-std/Test.sol';
import {console} from 'forge-std/console.sol';

import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {USDCVaultDDW} from 'contracts/USDCVaultDDW.sol';
import {MetisIntegrationBase} from '../integration/MetisIntegrationBase.sol';

contract USDCVaultWithdrawalConstructor is MetisIntegrationBase {
  function test_OwnerSet() public {
    _psm = new USDCVaultDDW();
    _psm.initialize(100, 100, address(_maiToken), address(_usdcToken));

    assertEq(_psm.owner(), address(_owner));
  }
}

contract USDCVaultAdminSuite is USDCVaultWithdrawalConstructor {
  event FeesWithdrawn(address indexed owner, uint256 feesEarned);

  function test_TransferOwnership() public {
    _psm = new USDCVaultDDW();
    _psm.initialize(100, 100, address(_maiToken), address(_usdcToken));

    vm.expectRevert(USDCVaultDDW.NewOwnerCannotBeZeroAddress.selector);
    _psm.transferOwnership(address(0x0));

    _psm.transferOwnership(address(_user));
    assertEq(_psm.owner(), address(_user));

    vm.expectRevert(USDCVaultDDW.CallerIsNotOwner.selector);
    _psm.transferOwnership(address(0));
  }

  function test_UpdateMaxDepositWithdraw() public {
    _psm = new USDCVaultDDW();
    _psm.initialize(100, 200, address(_maiToken), address(_usdcToken));

    _psm.updateMax(200, 3000);
    assertEq(_psm.maxDeposit(), 200);
    assertEq(_psm.maxWithdraw(), 3000);
  }

  function test_UpdateFeesBP() public {
    _psm = new USDCVaultDDW();
    _psm.initialize(100, 100, address(_maiToken), address(_usdcToken));

    assertEq(_psm.depositFee(), 100);
    assertEq(_psm.withdrawalFee(), 100);
    _psm.updateFeesBP(200, 200);
    assertEq(_psm.depositFee(), 200);
    assertEq(_psm.withdrawalFee(), 200);
  }

  function test_UpdateMinimumFees() public {
    _psm = new USDCVaultDDW();
    _psm.initialize(100, 100, address(_maiToken), address(_usdcToken));
    _psm.updateMinimumFees(200, 200);
    assertEq(_psm.minimumDepositFee(), 200);
    assertEq(_psm.minimumWithdrawalFee(), 200);
  }

  function test_ClaimFees() public {
    _psm = new USDCVaultDDW();
    _psm.initialize(0, 0, address(_maiToken), address(_usdcToken));
    _psm.updateMax(2000 * 10 ** 6, 2000 * 10 ** 6);
    _psm.updateMinimumFees(0, 0);

    vm.startPrank(_owner);
    deal(address(_usdcToken), _owner, 10_000_000_000 * 10 ** 6);
    deal(address(_maiToken), address(_psm), 10_000_000_000 ether);
    _usdcToken.approve(address(_psm), 1000 * 10 ** 6);
    console.log('USDC balance:', _usdcToken.balanceOf(_owner));
    _psm.deposit(1000 * 10 ** 6);

    _usdcToken.approve(address(_psm), 1000 * 10 ** 6);
    _psm.deposit(1000 * 10 ** 6);

    uint256 feesBefore = _usdcToken.balanceOf(_owner);

    _psm.claimFees();
    uint256 feesAfter = _usdcToken.balanceOf(_owner);
    uint256 feesClaimed = feesAfter - feesBefore;
    console.log('Fees claimed:', feesClaimed);
  }

  function test_TransferTokenWithoutUpgradeSet() public {
    deal(address(_usdcToken), address(_psm), 1000 * 10 ** 6); // 1000 USDC with 6 decimals
    uint256 _usdcTokenBalance = _usdcToken.balanceOf(address(_psm));
    console.log('transferToken usdcToken balance:', _usdcTokenBalance);
    vm.expectRevert(USDCVaultDDW.UpgradeNotScheduled.selector);
    _psm.transferToken(address(_usdcToken), address(_user), _usdcTokenBalance);
    _psm.setUpgrade();
    vm.warp(block.timestamp + 4 days);
    _psm.transferToken(address(_usdcToken), address(_user), _usdcTokenBalance);
    assertEq(_usdcToken.balanceOf(address(_psm)), 0);
  }
}

contract PsmDepositSuite is USDCVaultWithdrawalConstructor {
  event Deposited(address indexed user, uint256 amount);

  function test_Initialized() public {
    _psm = new USDCVaultDDW();
    _psm.initialize(100, 100, address(_maiToken), address(_usdcToken));

    assertEq(_psm.initialized(), true);
    vm.expectRevert();
    _psm.initialize(100, 100, address(_maiToken), address(_usdcToken));
  }

  function test_RevertIfPaused() public {
    _psm.setPaused(USDCVaultDDW.deposit.selector, true);
    vm.expectRevert(USDCVaultDDW.ContractIsPaused.selector);
    _psm.deposit(100_000_000);
  }

  function test_Deposit_ZeroAmountReverts() public {
    uint256 _amount = 0;
    vm.expectRevert(USDCVaultDDW.InvalidAmount.selector);
    _psm.deposit(_amount);
  }

  function test_Deposit_ZeroMaibalanceReverts() public {
    uint256 _amount = 1000 * 10 ** 6; // 1000 USDC with 6 decimals
    _usdcToken.approve(address(_psm), _amount);
    _psm.withdrawMAI();
    vm.expectRevert(USDCVaultDDW.InsufficientMAIBalance.selector);
    _psm.deposit(_amount);
  }

  function test_Deposit(
    uint256 _amount
  ) public {
    bound(_amount, 0, _usdcToken.balanceOf(msg.sender));
    // Verify that the deposit amount is within the allowed range for deposits
    uint256 maxDeposit = _psm.maxDeposit();
    uint256 minDeposit = _psm.minimumDepositFee();
    if (_amount < minDeposit || _amount > maxDeposit) {
      console.log('Deposit amount too small or too large');
      vm.expectRevert(USDCVaultDDW.InvalidAmount.selector);
      _psm.deposit(_amount);
      return;
    }

    // Verify that the withdrawal amount is within the allowed range for withdrawals
    uint256 maxWithdraw = _psm.maxWithdraw();
    uint256 minWithdraw = _psm.minimumWithdrawalFee();
    if (_amount < minWithdraw || _amount > maxWithdraw) {
      console.log('Withdraw amount too small or too large');
      vm.expectRevert(USDCVaultDDW.InvalidAmount.selector);
      _psm.deposit(_amount);
      return;
    }

    // Calculate the expected fee

    vm.startPrank(_user);
    bound(_amount, 0, _usdcToken.balanceOf(_user) - 1);
    uint256 expectedFee = _psm.calculateFee(_amount, true);
    _usdcToken.approve(address(_psm), _amount);
    // If the deposit amount is less than or equal to the minimumDepositFee or the fee, expect a revert
    console.log('Deposit amount:      ', _amount);
    console.log('token balance:       ', _usdcToken.balanceOf(_user));
    console.log('maxDeposit:          ', _psm.maxDeposit());
    console.log('minimumDepositFee:   ', _psm.minimumDepositFee());
    if (_amount > _usdcToken.balanceOf(_user)) {
      console.log('Deposit amount too large');
      vm.expectRevert();
      _psm.deposit(_amount);
      return;
    }
    if (_amount <= _psm.minimumDepositFee() || _amount <= expectedFee) {
      console.log('Deposit amount too small or too large');
      vm.expectRevert(USDCVaultDDW.InvalidAmount.selector);
      _psm.deposit(_amount);
      return;
    } else {
      // Expect the Deposited event to be emitted with the correct parameters
      // vm.expectEmit(true, false, false, true);
      // emit Deposited(_user, _amount - expectedFee);
      uint256 amtBefore = _usdcToken.balanceOf(_user);
      uint256 maiBalanceBefore = _maiToken.balanceOf(_user);
      _psm.deposit(_amount);
      uint256 amtAfter = _usdcToken.balanceOf(_user);
      uint256 maiBalanceAfter = _maiToken.balanceOf(_user);

      assertEq(amtBefore - _amount, amtAfter, 'Users token balance should decrease by the deposit amount');
      // Convert USDC amount to MAI scale (multiply by 10^12)
      uint256 expectedMAIIncrease = (_amount - expectedFee) * 10 ** 12;
      assertEq(
        (maiBalanceAfter - maiBalanceBefore),
        expectedMAIIncrease,
        'Users MAI balance should increase by the deposit amount minus the fee'
      );
    }
  }

  function test_DepositWithZeroFee() public {
    USDCVaultDDW __psm = new USDCVaultDDW();
    __psm.initialize(0, 0, address(_maiToken), address(_usdcToken));
    __psm.updateMinimumFees(0, 0);
    deal(address(_maiToken), address(__psm), 100_000_000 ether);
    uint256 usdcAmount = 1000 * 10 ** 6; // 1000 USDC with 6 decimals
    _usdcToken.approve(address(__psm), usdcAmount);
    __psm.deposit(usdcAmount);
    // MAI has 18 decimals, so 1000 USDC (6 decimals) becomes 1000 * 10^12 = 1000 * 10^18 / 10^6 = 1000 ether MAI
    assertEq(_maiToken.balanceOf(address(_owner)), 1000 ether);
    assertEq(__psm.depositFee(), 0);
    assertEq(__psm.withdrawalFee(), 0);
  }
}

contract USDCVaultWithdrawSuite is USDCVaultWithdrawalConstructor {
  event Withdrawn(address indexed user, uint256 amount);

  function test_RevertIfPaused() public {
    _psm.setPaused(USDCVaultDDW.scheduleWithdraw.selector, true);

    vm.expectRevert(USDCVaultDDW.ContractIsPaused.selector);
    _psm.scheduleWithdraw(1000);
  }

  function test_DoubleWithdrawReverts() public {
    uint256 depositAmount = 1000 * 10 ** 6; // 1000 USDC with 6 decimals
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);
    console.log('maiToken balance before:', _maiToken.balanceOf(_owner));

    _maiToken.approve(address(_psm), _maiToken.balanceOf(_owner));
    _psm.scheduleWithdraw(_maiToken.balanceOf(_owner));
    uint256 _maiBalanceAfter = _maiToken.balanceOf(_owner);
    // MOOSE
    vm.expectRevert(USDCVaultDDW.WithdrawalAlreadyScheduled.selector);
    _psm.scheduleWithdraw(_maiBalanceAfter);
  }

  function test_Withdraw_BeforeEpochReverts() public {
    uint256 depositAmount = 1000 * 10 ** 6; // 1000 USDC with 6 decimals
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);
    _maiToken.approve(address(_psm), _maiToken.balanceOf(_owner));
    _psm.scheduleWithdraw(100 * 10 ** 18); // 100 MAI with 18 decimals
    vm.expectRevert(USDCVaultDDW.WithdrawalNotAvailable.selector);
    _psm.withdraw();
  }

  function test_Withdraw_NoScheduledWithdrawalReverts() public {
    vm.expectRevert(USDCVaultDDW.WithdrawalNotAvailable.selector);
    _psm.withdraw();
  }

  function test_DepositAndWithdraw(uint256 _depositAmount, uint256 _withdrawAmount) public {
    // USDC has 6 decimals, so minimum reasonable amount is 1 USDC = 1e6
    uint256 userBalance = _usdcToken.balanceOf(_user);
    if (userBalance < 1 * 10 ** 6) {
      return; // Skip test if user has less than 1 USDC
    }
    _depositAmount = bound(_depositAmount, 1 * 10 ** 6, userBalance);
    // Withdrawal amount should be in MAI scale, but not exceed what user will receive after deposit
    uint256 expectedDepositFee = _psm.calculateFee(_depositAmount, true);
    uint256 maxMAIReceived = (_depositAmount - expectedDepositFee) * 10 ** 12;

    // If the max MAI received is less than minimum withdrawal, skip this test case
    if (maxMAIReceived < 1 * 10 ** 18) {
      return;
    }

    _withdrawAmount = bound(_withdrawAmount, 1 * 10 ** 18, maxMAIReceived);
    // Deposit first to ensure there are tokens to withdraw
    _usdcToken.approve(address(_psm), _depositAmount);
    console.log('Deposit amount:', _depositAmount);
    console.log('maxDeposit:', _psm.maxDeposit());
    console.log('minimumDepositFee:', _psm.minimumDepositFee());
    console.log('USDC balance before:', _usdcToken.balanceOf(address(_psm)));

    if (_depositAmount <= _psm.minimumDepositFee() || _depositAmount > _psm.maxDeposit()) {
      console.log('Deposit amount too small or too large');
      vm.expectRevert(USDCVaultDDW.InvalidAmount.selector);
      _psm.deposit(_depositAmount);
      return;
    } else {
      uint256 _expectedFee = _psm.calculateFee(_depositAmount, true);
      uint256 _amtBefore = _usdcToken.balanceOf(_owner);
      uint256 _maiBalanceBeforeDeposit = _maiToken.balanceOf(_owner);
      _psm.deposit(_depositAmount);
      uint256 _amtAfter = _usdcToken.balanceOf(_owner);
      uint256 _maiBalanceAfter = _maiToken.balanceOf(_owner);
      assertApproxEqAbs(
        _amtBefore, _amtAfter + _depositAmount, 10, 'Users token BALANCE should decrease by the deposit amount'
      );
      // Convert USDC amount to MAI scale (multiply by 10^12)
      uint256 expectedMAIIncrease = (_depositAmount - _expectedFee) * 10 ** 12;
      assertApproxEqAbs(
        (_maiBalanceAfter - _maiBalanceBeforeDeposit),
        expectedMAIIncrease,
        10,
        'Users MAI balance should increase by the deposit amount minus the fee'
      );
    }
    console.log('USDC balance after:', _usdcToken.balanceOf(address(_psm)));
    uint256 _maiBalanceBefore = _maiToken.balanceOf(_owner);

    _maiToken.approve(address(_psm), _withdrawAmount);

    // Schedule the withdrawal
    uint256 withdrawAmountUSDC = _withdrawAmount / 10 ** 12; // Convert MAI to USDC
    if ((_psm.totalStableLiquidity() - _psm.totalQueuedLiquidity()) < withdrawAmountUSDC) {
      console.log('Not enough liquidity');
      vm.expectRevert(USDCVaultDDW.NotEnoughLiquidity.selector);
      _psm.scheduleWithdraw(_withdrawAmount);
      return;
    } else if (_withdrawAmount > _maiToken.balanceOf(address(_psm))) {
      console.log('Withdraw amount too large');
      vm.expectRevert(USDCVaultDDW.InvalidAmount.selector);
      _psm.scheduleWithdraw(_withdrawAmount);
      return;
    } else if (
      _withdrawAmount < _psm.minimumWithdrawalFee() * 10 ** 12 || _withdrawAmount > _psm.maxWithdraw() * 10 ** 12
    ) {
      console.log('Withdraw Amount too small or too large');
      vm.expectRevert(USDCVaultDDW.InvalidAmount.selector);
      _psm.scheduleWithdraw(_withdrawAmount);
      return;
    } else {
      _psm.scheduleWithdraw(_withdrawAmount);
      uint256 _maiBalanceAfterSchedule = _maiToken.balanceOf(_owner);
      assertApproxEqAbs(
        _maiBalanceAfterSchedule,
        _maiBalanceBefore - _withdrawAmount,
        10,
        'Users MAI balance should decrease by the withdrawal amount'
      );
    }

    // Move forward in time to the next epoch to simulate the passage of time for withdrawal execution
    vm.warp(block.timestamp + 4 days);
    // Execute the withdrawal
    console.log('totalStableLiquidity:      ', _psm.totalStableLiquidity());
    console.log('withdrawAmount:            ', _withdrawAmount);
    if (_psm.totalStableLiquidity() < withdrawAmountUSDC) {
      console.log('Not enough liquidity');
      vm.expectRevert(USDCVaultDDW.NotEnoughLiquidity.selector);
      _psm.withdraw();
    } else if (withdrawAmountUSDC > _depositAmount) {
      console.log('Withdraw amount too large');
      vm.expectRevert(USDCVaultDDW.InvalidAmount.selector);
      _psm.withdraw();
    } else if (
      _withdrawAmount < _psm.minimumWithdrawalFee() * 10 ** 12 || _withdrawAmount > _psm.maxWithdraw() * 10 ** 12
    ) {
      console.log('Invalid amount');
      vm.expectRevert(USDCVaultDDW.InvalidAmount.selector);
      _psm.withdraw();
    } else {
      vm.expectEmit(false, false, false, false);
      emit Withdrawn(_user, _withdrawAmount);
      console.log('owner:                     ', _owner);
      console.log('user:                      ', _user);
      uint256 _amtBefore = _usdcToken.balanceOf(_owner);
      _psm.withdraw();
      uint256 _withdrawFee = _psm.calculateFee(withdrawAmountUSDC, false);
      uint256 _maiBalanceAfter = _maiToken.balanceOf(_owner);
      uint256 _amtAfter = _usdcToken.balanceOf(_owner);

      console.log('_usdcTokenAddress:         ', address(_usdcToken));
      console.log('maiBalanceBefore:          ', _maiBalanceBefore);
      console.log('maiBalanceAfter:           ', _maiBalanceAfter);
      console.log('amtBefore:                 ', _amtBefore);
      console.log('amtAfter:                  ', _amtAfter);
      console.log('amtDiff:                   ', _amtAfter - _amtBefore);
      console.log('withdrawFee:               ', _withdrawFee);
      console.log('withdrawAmount:            ', _withdrawAmount);
      console.log('withdrawDiff:              ', withdrawAmountUSDC - _withdrawFee);
      assertApproxEqAbs(
        _amtAfter - _amtBefore,
        withdrawAmountUSDC - _withdrawFee,
        100,
        'Users token balance should increase by the withdrawal amount'
      );
      assertApproxEqAbs(
        _maiBalanceBefore,
        _maiToken.balanceOf(_owner) + _withdrawAmount,
        10_000,
        'Users MAI balance should decrease by the withdrawal amount'
      );
      assertGe(_usdcToken.balanceOf(_owner), 0);
      assertGe(_usdcToken.balanceOf(address(_psm)), 0);
      _psm.claimFees();
      //                                    depositAmount   withdrawFee
      _psm.setUpgrade();
      vm.warp(block.timestamp + 4 days);
      _psm.transferToken(address(_usdcToken), address(_owner), _usdcToken.balanceOf(address(_psm)));
      assertEq(_usdcToken.balanceOf(address(_psm)), 0, 'usdcToken balance should be 0');

      _psm.transferToken(address(_usdcToken), address(_owner), _usdcToken.balanceOf(address(_psm)));
      assertEq(_usdcToken.balanceOf(address(_psm)), 0, 'USDC balance should be 0');

      _psm.withdrawMAI();
      assertEq(_maiToken.balanceOf(address(_psm)), 0, 'MAI balance should be 0');
    }
  }
}

contract USDCVaultDecimalConversionSuite is USDCVaultWithdrawalConstructor {
  event Deposited(address indexed user, uint256 amount);
  event WithdrawalScheduled(address indexed user, uint256 amount);

  function test_DecimalConversion() public {
    // Test USDC (6 decimals) to MAI (18 decimals) conversion
    uint256 usdcAmount = 1000 * 10 ** 6; // 1000 USDC
    uint256 depositFee = _psm.calculateFee(usdcAmount, true);
    uint256 netUsdcAmount = usdcAmount - depositFee;
    uint256 expectedMAI = netUsdcAmount * 10 ** 12; // Convert to 18 decimals

    _usdcToken.approve(address(_psm), usdcAmount);

    // Expect the Deposited event with correct amount
    vm.expectEmit(true, false, false, true);
    emit Deposited(_owner, netUsdcAmount);

    _psm.deposit(usdcAmount);

    assertEq(_maiToken.balanceOf(_owner), expectedMAI, 'MAI balance should match expected conversion');
  }

  function test_WithdrawalDecimalConversion() public {
    // First deposit some USDC
    uint256 usdcDepositAmount = 1000 * 10 ** 6; // 1000 USDC
    _usdcToken.approve(address(_psm), usdcDepositAmount);
    _psm.deposit(usdcDepositAmount);

    // Now test withdrawal conversion
    uint256 maiWithdrawAmount = 500 * 10 ** 18; // 500 MAI
    uint256 expectedUSDC = maiWithdrawAmount / 10 ** 12; // Convert to 6 decimals

    _maiToken.approve(address(_psm), maiWithdrawAmount);

    // Expect the WithdrawalScheduled event
    vm.expectEmit(true, false, false, true);
    emit WithdrawalScheduled(_owner, maiWithdrawAmount);

    _psm.scheduleWithdraw(maiWithdrawAmount);

    // Fast forward and withdraw
    vm.warp(block.timestamp + 4 days);

    uint256 usdcBalanceBefore = _usdcToken.balanceOf(_owner);
    _psm.withdraw();
    uint256 usdcBalanceAfter = _usdcToken.balanceOf(_owner);

    uint256 withdrawFee = _psm.calculateFee(expectedUSDC, false);
    uint256 expectedUSDCAfterFee = expectedUSDC - withdrawFee;

    assertEq(
      usdcBalanceAfter - usdcBalanceBefore,
      expectedUSDCAfterFee,
      'USDC received should match expected conversion minus fee'
    );
  }

  function test_SmallAmountDecimalHandling() public {
    // Test with small amounts to ensure no rounding issues
    uint256 smallUsdcAmount = 10 * 10 ** 6; // 10 USDC
    _psm.updateMinimumFees(1 * 10 ** 6, 1 * 10 ** 6); // Set low minimum fees

    _usdcToken.approve(address(_psm), smallUsdcAmount);
    _psm.deposit(smallUsdcAmount);

    // MAI balance should be (10 - fee) * 10^12
    uint256 fee = _psm.calculateFee(smallUsdcAmount, true);
    uint256 expectedMAI = (smallUsdcAmount - fee) * 10 ** 12;
    assertEq(_maiToken.balanceOf(_owner), expectedMAI, 'Small amount conversion should be correct');
  }
}

contract USDCVaultPausableSuite is USDCVaultWithdrawalConstructor {
  function test_PausableWithUpgrade() public {
    // Set upgrade which sets stopped = true and upgradeTime = now + 2 days
    _psm.setUpgrade();

    // Before upgrade time, functions should still work
    vm.warp(block.timestamp + 1 days);
    uint256 depositAmount = 100 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount); // Should work

    // After upgrade time, functions should be paused
    vm.warp(block.timestamp + 2 days); // Total 3 days after setUpgrade

    _usdcToken.approve(address(_psm), depositAmount);
    vm.expectRevert(USDCVaultDDW.ContractIsPaused.selector);
    _psm.deposit(depositAmount);

    // Test other pausable functions
    vm.expectRevert(USDCVaultDDW.ContractIsPaused.selector);
    _psm.scheduleWithdraw(50 * 10 ** 18);

    vm.expectRevert(USDCVaultDDW.ContractIsPaused.selector);
    _psm.withdraw();
  }

  function test_PausedBySelector() public {
    // Test pausing specific functions
    _psm.setPaused(USDCVaultDDW.deposit.selector, true);
    _psm.setPaused(USDCVaultDDW.scheduleWithdraw.selector, false);

    // Deposit should be paused
    uint256 depositAmount = 100 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    vm.expectRevert(USDCVaultDDW.ContractIsPaused.selector);
    _psm.deposit(depositAmount);

    // But first need to deposit through a different method or unpause
    _psm.setPaused(USDCVaultDDW.deposit.selector, false);
    _psm.deposit(depositAmount);

    // Schedule withdraw should work since it's not paused
    _maiToken.approve(address(_psm), 50 * 10 ** 18);
    _psm.scheduleWithdraw(50 * 10 ** 18); // Should not revert
  }
}

contract USDCVaultMultiUserSuite is USDCVaultWithdrawalConstructor {
  address internal _user2 = makeAddr('user2');
  address internal _user3 = makeAddr('user3');

  function setUp() public override {
    super.setUp();
    // Give USDC to additional users
    deal(address(_usdcToken), _user2, 100_000_000 * 10 ** 6);
    deal(address(_usdcToken), _user3, 100_000_000 * 10 ** 6);
  }

  function test_MultipleUsersQueuedLiquidity() public {
    // Setup: Each user deposits 1000 USDC
    uint256 depositAmount = 1000 * 10 ** 6;

    // User 1 deposits
    vm.startPrank(_user);
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);
    vm.stopPrank();

    // User 2 deposits
    vm.startPrank(_user2);
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);
    vm.stopPrank();

    // User 3 deposits
    vm.startPrank(_user3);
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);
    vm.stopPrank();

    // Check total liquidity (minus fees)
    uint256 feePerDeposit = _psm.calculateFee(depositAmount, true);
    uint256 expectedTotalLiquidity = 3 * (depositAmount - feePerDeposit);
    assertEq(_psm.totalStableLiquidity(), expectedTotalLiquidity, 'Total liquidity should match deposits minus fees');

    // Each user schedules withdrawal of 500 MAI
    uint256 withdrawAmount = 500 * 10 ** 18; // 500 MAI
    uint256 withdrawAmountUSDC = withdrawAmount / 10 ** 12; // 500 USDC

    // User 1 schedules withdrawal
    vm.startPrank(_user);
    _maiToken.approve(address(_psm), withdrawAmount);
    _psm.scheduleWithdraw(withdrawAmount);
    vm.stopPrank();

    assertEq(_psm.totalQueuedLiquidity(), withdrawAmountUSDC, 'Queued liquidity should match user 1 withdrawal');

    // User 2 schedules withdrawal
    vm.startPrank(_user2);
    _maiToken.approve(address(_psm), withdrawAmount);
    _psm.scheduleWithdraw(withdrawAmount);
    vm.stopPrank();

    assertEq(_psm.totalQueuedLiquidity(), 2 * withdrawAmountUSDC, 'Queued liquidity should match both withdrawals');

    // User 3 schedules withdrawal
    vm.startPrank(_user3);
    _maiToken.approve(address(_psm), withdrawAmount);
    _psm.scheduleWithdraw(withdrawAmount);
    vm.stopPrank();

    assertEq(_psm.totalQueuedLiquidity(), 3 * withdrawAmountUSDC, 'Queued liquidity should match all three withdrawals');

    // Verify available liquidity
    uint256 availableLiquidity = _psm.totalStableLiquidity() - _psm.totalQueuedLiquidity();
    uint256 expectedAvailable = expectedTotalLiquidity - (3 * withdrawAmountUSDC);
    assertEq(availableLiquidity, expectedAvailable, 'Available liquidity should be total minus queued');

    // Fast forward and process withdrawals
    vm.warp(block.timestamp + 4 days);

    // User 1 withdraws
    vm.startPrank(_user);
    uint256 user1BalanceBefore = _usdcToken.balanceOf(_user);
    _psm.withdraw();
    uint256 user1BalanceAfter = _usdcToken.balanceOf(_user);
    vm.stopPrank();

    uint256 withdrawFee = _psm.calculateFee(withdrawAmountUSDC, false);
    assertEq(
      user1BalanceAfter - user1BalanceBefore,
      withdrawAmountUSDC - withdrawFee,
      'User 1 should receive withdrawal minus fee'
    );

    // Check that queued liquidity decreased
    assertEq(_psm.totalQueuedLiquidity(), 2 * withdrawAmountUSDC, 'Queued liquidity should decrease after withdrawal');

    // Check that total liquidity decreased
    assertEq(
      _psm.totalStableLiquidity(),
      expectedTotalLiquidity - withdrawAmountUSDC,
      'Total liquidity should decrease after withdrawal'
    );
  }

  function test_InsufficientLiquidityForAllUsers() public {
    // Setup: Only two users deposit, but three try to withdraw
    uint256 depositAmount = 500 * 10 ** 6; // 500 USDC

    // User 1 deposits
    vm.startPrank(_user);
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);
    vm.stopPrank();

    // User 2 deposits
    vm.startPrank(_user2);
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);
    vm.stopPrank();

    // Calculate how much MAI each depositor received
    uint256 feePerDeposit = _psm.calculateFee(depositAmount, true);
    uint256 maiReceivedPerUser = (depositAmount - feePerDeposit) * 10 ** 12;

    // Give User 3 some MAI tokens to try to withdraw (even though they didn't deposit)
    deal(address(_maiToken), _user3, maiReceivedPerUser);

    // First two users schedule withdrawals - this should use up all liquidity
    vm.startPrank(_user);
    _maiToken.approve(address(_psm), maiReceivedPerUser);
    _psm.scheduleWithdraw(maiReceivedPerUser);
    vm.stopPrank();

    vm.startPrank(_user2);
    _maiToken.approve(address(_psm), maiReceivedPerUser);
    _psm.scheduleWithdraw(maiReceivedPerUser);
    vm.stopPrank();

    // Third user should fail because there's not enough USDC liquidity left
    // (only 2 users deposited but 3 are trying to withdraw)
    vm.startPrank(_user3);
    _maiToken.approve(address(_psm), maiReceivedPerUser);
    vm.expectRevert(USDCVaultDDW.NotEnoughLiquidity.selector);
    _psm.scheduleWithdraw(maiReceivedPerUser);
    vm.stopPrank();
  }
}

contract USDCVaultEdgeCasesSuite is USDCVaultWithdrawalConstructor {
  function test_FeeGreaterThanAmount() public {
    // Set very high fees
    _psm.updateFeesBP(9999, 9999); // 99.99% fee
    _psm.updateMinimumFees(0, 0);

    uint256 depositAmount = 100 * 10 ** 6; // 100 USDC
    uint256 fee = _psm.calculateFee(depositAmount, true);

    // Fee should be 99.99 USDC, leaving only 0.01 USDC
    assertEq(fee, 9999 * depositAmount / 10_000, 'Fee calculation should be correct');

    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    // User should receive very small amount of MAI
    uint256 expectedMAI = (depositAmount - fee) * 10 ** 12;
    assertEq(_maiToken.balanceOf(_owner), expectedMAI, 'Should receive tiny amount after huge fee');
  }

  function test_ExactBoundaryValues() public {
    // Set a non-zero minimum deposit fee first
    _psm.updateMinimumFees(10 * 10 ** 6, 10 * 10 ** 6); // 10 USDC minimum

    // Test exact minimum deposit
    uint256 minDeposit = _psm.minimumDepositFee();
    _usdcToken.approve(address(_psm), minDeposit);
    vm.expectRevert(USDCVaultDDW.InvalidAmount.selector);
    _psm.deposit(minDeposit); // Should fail as amount <= minimumDepositFee

    // Test just above minimum
    _usdcToken.approve(address(_psm), minDeposit + 1);
    _psm.deposit(minDeposit + 1); // Should succeed

    // Test exact maximum deposit
    _psm.updateMax(1000 * 10 ** 6, 1000 * 10 ** 6); // Set reasonable max
    uint256 maxDeposit = _psm.maxDeposit();
    deal(address(_usdcToken), _owner, maxDeposit + 100 * 10 ** 6);

    _usdcToken.approve(address(_psm), maxDeposit);
    _psm.deposit(maxDeposit); // Should succeed

    // Test above maximum
    _usdcToken.approve(address(_psm), maxDeposit + 1);
    vm.expectRevert(USDCVaultDDW.InvalidAmount.selector);
    _psm.deposit(maxDeposit + 1); // Should fail
  }

  function test_CancelWithdrawalNotImplemented() public {
    // Note: The contract doesn't have a cancelWithdrawal function
    // This test documents this limitation

    // User deposits and schedules withdrawal
    uint256 depositAmount = 1000 * 10 ** 6;
    _usdcToken.approve(address(_psm), depositAmount);
    _psm.deposit(depositAmount);

    uint256 withdrawAmount = 500 * 10 ** 18;
    _maiToken.approve(address(_psm), withdrawAmount);
    _psm.scheduleWithdraw(withdrawAmount);

    // User cannot cancel the withdrawal
    // They must wait for the epoch and execute it
    assertEq(_psm.withdrawalEpoch(_owner), block.timestamp + 3 days, 'Withdrawal is scheduled');
    assertEq(_psm.scheduledWithdrawalAmount(_owner), withdrawAmount, 'Amount is locked');

    // Only way to "cancel" is to execute the withdrawal and redeposit
  }
}
