// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {Test} from 'forge-std/Test.sol';
import {IBeefy} from '../../interfaces/IBeefy.sol';
import {BeefyVaultPSM} from '../../contracts/BeefyVaultDDW.sol';
import 'forge-std/console.sol';
import {BeefyIntegrationBase} from '../integration/BeefyIntegrationBase.sol';
import {StdCheats} from 'forge-std/StdCheats.sol';

contract PsmWithdrawalConstructor is BeefyIntegrationBase {
  function test_OwnerSet() public {
    _psm = new BeefyVaultPSM();
    _psm.initialize(address(_mooToken), 100, 100);

    assertEq(_psm.owner(), address(_owner));
  }

  function test_TokenSet() public {
    _psm = new BeefyVaultPSM();
    _psm.initialize(address(_mooToken), 100, 100);

    assertEq(address(_psm.gem()), address(_mooToken));
  }

  function test_BeefySet() public {
    _psm = new BeefyVaultPSM();
    _psm.initialize(address(_mooToken), 100, 100);
    assertEq(address(_psm.underlying()), address(_usdbcToken));
  }
}

contract PsmAdminSuite is PsmWithdrawalConstructor {
  event FeesWithdrawn(address indexed owner, uint256 feesEarned);

  function test_TransferOwnership() public {
    _psm = new BeefyVaultPSM();
    _psm.initialize(address(_mooToken), 100, 100);

    vm.expectRevert(BeefyVaultPSM.NewOwnerCannotBeZeroAddress.selector);
    _psm.transferOwnership(address(0x0));

    _psm.transferOwnership(address(_user));
    assertEq(_psm.owner(), address(_user));

    vm.expectRevert(BeefyVaultPSM.CallerIsNotOwner.selector);
    _psm.transferOwnership(address(0));
  }

  function test_UpdateMaxDepositWithdraw() public {
    _psm = new BeefyVaultPSM();
    _psm.initialize(address(_mooToken), 100, 200);

    _psm.updateMax(200, 3000);
    assertEq(_psm.maxDeposit(), 200);
    assertEq(_psm.maxWithdraw(), 3000);
  }

  function test_UpdateFeesBP() public {
    _psm = new BeefyVaultPSM();
    _psm.initialize(address(_mooToken), 100, 100);

    assertEq(_psm.depositFee(), 100);
    assertEq(_psm.withdrawalFee(), 100);
    _psm.updateFeesBP(200, 200);
    assertEq(_psm.depositFee(), 200);
    assertEq(_psm.withdrawalFee(), 200);
  }

  function test_UpdateMinimumFees() public {
    _psm = new BeefyVaultPSM();
    _psm.initialize(address(_mooToken), 100, 100);
    _psm.updateMinimumFees(200, 200);
    assertEq(_psm.minimumDepositFee(), 200);
    assertEq(_psm.minimumWithdrawalFee(), 200);
  }

  function test_ClaimFees() public {
    _psm = new BeefyVaultPSM();
    _psm.initialize(address(_mooToken), 100, 100);
    _beefyVault = IBeefy(address(_mooToken));

    vm.startPrank(_owner);
    deal(address(_usdbcToken), _owner, 10_000_000_000 * 10 ** 6);
    deal(address(_maiToken), address(_psm), 10_000_000_000 * 10 ** 18);
    _usdbcToken.approve(address(_psm), 1000 * 10 ** 6);
    console.log('usdc balance:', _usdbcToken.balanceOf(_owner));
    _psm.deposit(1000 * 10 ** 6);

    _usdbcToken.approve(address(_beefyVault), 1000 * 10 ** 6);
    _beefyVault.deposit(1000 * 10 ** 6);
    _mooToken.transfer(address(_psm), _mooToken.balanceOf(_owner));

    emit FeesWithdrawn(_owner, 0);
    vm.expectEmit(true, false, false, false);
    _psm.claimFees();
  }

  function test_TransferTokenWithoutUpgradeSet() public {
    deal(address(_mooToken), address(_psm), 1000 * 10 ** 18);
    uint256 _mooTokenBalance = _mooToken.balanceOf(address(_psm));
    console.log('transferToken mooToken balance:', _mooTokenBalance);
    vm.expectRevert(BeefyVaultPSM.UpgradeNotScheduled.selector);
    _psm.transferToken(address(_mooToken), address(_user), _mooTokenBalance);
    _psm.setUpgrade();
    vm.warp(block.timestamp + 4 days);
    _psm.transferToken(address(_mooToken), address(_user), _mooTokenBalance);
    assertEq(_mooToken.balanceOf(address(_psm)), 0);
  }
}

contract PsmDepositSuite is PsmWithdrawalConstructor {
  event Deposited(address indexed user, uint256 amount);

  function test_Initialized() public {
    _psm = new BeefyVaultPSM();
    _psm.initialize(address(_mooToken), 100, 100);

    assertEq(_psm.initialized(), true);
    vm.expectRevert();
    _psm.initialize(address(_mooToken), 100, 100);
  }

  function test_RevertIfPaused() public {
    _psm.setPaused(BeefyVaultPSM.deposit.selector, true);
    vm.expectRevert(BeefyVaultPSM.ContractIsPaused.selector);
    _psm.deposit(100_000_000);
  }

  function test_Deposit_ZeroAmountReverts() public {
    uint256 _amount = 0;
    vm.expectRevert(BeefyVaultPSM.InvalidAmount.selector);
    _psm.deposit(_amount);
  }

  function test_Deposit_ZeroMaibalanceReverts() public {
    uint256 _amount = 1000 * 10 ** 6;
    _usdbcToken.approve(address(_psm), _amount);
    _psm.withdrawMAI();
    vm.expectRevert(BeefyVaultPSM.InsufficientMAIBalance.selector);
    _psm.deposit(_amount);
  }

  function test_Deposit(uint256 _amount) public {
    bound(_amount, 0, _usdbcToken.balanceOf(msg.sender));
    // Verify that the deposit amount is within the allowed range for deposits
    uint256 maxDeposit = _psm.maxDeposit();
    uint256 minDeposit = _psm.minimumDepositFee();
    if (_amount < minDeposit || _amount > maxDeposit) {
      console.log('Deposit amount too small or too large');
      vm.expectRevert(BeefyVaultPSM.InvalidAmount.selector);
      _psm.deposit(_amount);
      return;
    }

    // Verify that the withdrawal amount is within the allowed range for withdrawals
    uint256 maxWithdraw = _psm.maxWithdraw();
    uint256 minWithdraw = _psm.minimumWithdrawalFee();
    if (_amount < minWithdraw || _amount > maxWithdraw) {
      console.log('Withdraw amount too small or too large');
      vm.expectRevert(BeefyVaultPSM.InvalidAmount.selector);
      _psm.deposit(_amount);
      return;
    }

    // Calculate the expected fee

    vm.startPrank(_user);
    bound(_amount, 0, _usdbcToken.balanceOf(_user) - 1);
    uint256 expectedFee = _psm.calculateFee(_amount, true);
    _usdbcToken.approve(address(_psm), _amount);
    // If the deposit amount is less than or equal to the minimumDepositFee or the fee, expect a revert
    console.log('Deposit amount:      ', _amount);
    console.log('token balance:       ', _usdbcToken.balanceOf(_user));
    console.log('maxDeposit:          ', _psm.maxDeposit());
    console.log('minimumDepositFee:   ', _psm.minimumDepositFee());
    if (_amount > _usdbcToken.balanceOf(_user)) {
      console.log('Deposit amount too large');
      vm.expectRevert();
      _psm.deposit(_amount);
      return;
    }
    if (_amount <= _psm.minimumDepositFee() || _amount <= expectedFee) {
      console.log('Deposit amount too small or too large');
      vm.expectRevert(BeefyVaultPSM.InvalidAmount.selector);
      _psm.deposit(_amount);
      return;
    } else {
      // Expect the Deposited event to be emitted with the correct parameters
      // vm.expectEmit(true, false, false, true);
      // emit Deposited(_user, _amount - expectedFee);
      uint256 amtBefore = _usdbcToken.balanceOf(_user);
      uint256 maiBalanceBefore = _maiToken.balanceOf(_user);
      _psm.deposit(_amount);
      uint256 amtAfter = _usdbcToken.balanceOf(_user);
      uint256 maiBalanceAfter = _maiToken.balanceOf(_user);

      assertEq(amtBefore - _amount, amtAfter, 'Users token balance should decrease by the deposit amount');
      assertEq(
        (maiBalanceAfter - maiBalanceBefore) / 10 ** 12,
        _amount - expectedFee,
        'Users MAI balance should increase by the deposit amount minus the fee'
      );
    }
  }
}

contract PsmWithdrawSuite is PsmWithdrawalConstructor {
  event Withdrawn(address indexed user, uint256 amount);

  function test_RevertIfPaused() public {
    _psm.setPaused(BeefyVaultPSM.scheduleWithdraw.selector, true);

    vm.expectRevert(BeefyVaultPSM.ContractIsPaused.selector);
    _psm.scheduleWithdraw(1000);
  }

  function test_DoubleWithdrawReverts() public {
    _usdbcToken.approve(address(_psm), 1000 * 10 ** 6);
    _psm.deposit(1000 * 10 ** 6);
    _psm.scheduleWithdraw(100e18);
    vm.expectRevert(BeefyVaultPSM.WithdrawalAlreadyScheduled.selector);
    _psm.scheduleWithdraw(100e18);
  }

  function test_Withdraw_BeforeEpochReverts() public {
    _usdbcToken.approve(address(_psm), 1000 * 10 ** 6);
    _psm.deposit(1000 * 10 ** 6);
    _psm.scheduleWithdraw(100e18);
    vm.expectRevert(BeefyVaultPSM.WithdrawalNotAvailable.selector);
    _psm.withdraw();
  }

  function test_Withdraw_NoScheduledWithdrawalReverts() public {
    vm.expectRevert(BeefyVaultPSM.WithdrawalNotAvailable.selector);
    _psm.withdraw();
  }

  function test_DepositAndWithdraw(uint256 _depositAmount, uint256 _withdrawAmount) public {
    _depositAmount = bound(_depositAmount, 1e6, _usdbcToken.balanceOf(_user));
    _withdrawAmount = bound(_withdrawAmount, 1e18, _depositAmount * 10 ** 12);
    // Deposit first to ensure there are tokens to withdraw
    _usdbcToken.approve(address(_psm), _depositAmount);
    console.log('Deposit amount:', _depositAmount);
    console.log('maxDeposit:', _psm.maxDeposit());
    console.log('minimumDepositFee:', _psm.minimumDepositFee());
    console.log('mooToken balance bfore:', _mooToken.balanceOf(address(_psm)));

    if (_depositAmount <= _psm.minimumDepositFee() || _depositAmount > _psm.maxDeposit()) {
      console.log('Deposit amount too small or too large');
      vm.expectRevert(BeefyVaultPSM.InvalidAmount.selector);
      _psm.deposit(_depositAmount);
      return;
    } else {
      uint256 _expectedFee = _psm.calculateFee(_depositAmount, true);
      uint256 _amtBefore = _usdbcToken.balanceOf(_owner);
      uint256 _maiBalanceBefore = _maiToken.balanceOf(_owner);
      _psm.deposit(_depositAmount);
      uint256 _amtAfter = _usdbcToken.balanceOf(_owner);
      uint256 _maiBalanceAfter = _maiToken.balanceOf(_owner);
      assertApproxEqAbs(
        _amtBefore, _amtAfter + _depositAmount, 10, 'Users token BALANCE should decrease by the deposit amount'
      );
      assertApproxEqAbs(
        (_maiBalanceAfter - _maiBalanceBefore) / 10 ** 12,
        _depositAmount - _expectedFee,
        10,
        'Users MAI balance should increase by the deposit amount minus the fee'
      );
    }
    console.log('mooToken balance after:', _mooToken.balanceOf(address(_psm)));

    // Schedule the withdrawal
    if (_withdrawAmount < _psm.minimumWithdrawalFee() || _withdrawAmount > _psm.maxWithdraw()) {
      console.log('Withdraw Amount too small or too large');
      vm.expectRevert(BeefyVaultPSM.InvalidAmount.selector);
      _psm.scheduleWithdraw(_withdrawAmount);
      return;
    } else if ((_psm.totalStableLiquidity() - _psm.totalQueuedLiquidity()) < _withdrawAmount / 1e12) {
      console.log('Not enough liquidity');
      vm.expectRevert(BeefyVaultPSM.NotEnoughLiquidity.selector);
      _psm.scheduleWithdraw(_withdrawAmount);
      return;
    } else {
      _psm.scheduleWithdraw(_withdrawAmount);
    }

    // Move forward in time to the next epoch to simulate the passage of time for withdrawal execution
    vm.warp(block.timestamp + 4 days);
    // Execute the withdrawal
    console.log('totalStableLiquidity:      ', _psm.totalStableLiquidity());
    console.log('withdrawAmount:            ', _withdrawAmount);
    if (_psm.totalStableLiquidity() < _withdrawAmount / 1e12) {
      console.log('Not enough liquidity');
      vm.expectRevert(BeefyVaultPSM.NotEnoughLiquidity.selector);
      _psm.withdraw();
    } else if (_withdrawAmount > _depositAmount * 10 ** 12) {
      console.log('Withdraw amount too large');
      vm.expectRevert(BeefyVaultPSM.InvalidAmount.selector);
      _psm.withdraw();
    } else if (_withdrawAmount < _psm.minimumWithdrawalFee() || _withdrawAmount > _psm.maxWithdraw()) {
      console.log('Invalid amount');
      vm.expectRevert(BeefyVaultPSM.InvalidAmount.selector);
      _psm.withdraw();
    } else {
      vm.expectEmit(false, false, false, false);
      emit Withdrawn(_user, _withdrawAmount);
      console.log('owner:                     ', _owner);
      console.log('user:                      ', _user);
      uint256 _amtBefore = _usdbcToken.balanceOf(_owner);
      uint256 _maiBalanceBefore = _maiToken.balanceOf(_owner);
      _psm.withdraw();
      uint256 _withdrawFee = _psm.calculateFee(_withdrawAmount / 1e12, false);
      uint256 _maiBalanceAfter = _maiToken.balanceOf(_owner);
      uint256 _amtAfter = _usdbcToken.balanceOf(_owner);

      console.log('_usdcTokenAddress:         ', address(_usdbcToken));
      console.log('maiBalanceBefore:          ', _maiBalanceBefore);
      console.log('maiBalanceAfter:           ', _maiBalanceAfter);
      console.log('amtBefore:                 ', _amtBefore);
      console.log('amtAfter:                  ', _amtAfter);
      console.log('amtDiff:                   ', _amtAfter - _amtBefore);
      console.log('withdrawFee:               ', _withdrawFee);
      console.log('withdrawAmount:            ', _withdrawAmount / 1e12);
      console.log('withdrawDiff:              ', _withdrawAmount / 1e12 - _withdrawFee);
      assertApproxEqAbs(
        _amtAfter - _amtBefore,
        _withdrawAmount / 1e12 - _withdrawFee,
        100,
        'Users token balance should increase by the withdrawal amount'
      );
      assertApproxEqAbs(
        _maiBalanceBefore,
        _maiToken.balanceOf(_owner),
        100,
        'Users MAI balance should decrease by the withdrawal amount'
      );
      assertGe(_usdbcToken.balanceOf(_user), _withdrawAmount / 1e12);
      assertGe(_mooToken.balanceOf(address(_psm)), 0);
      _psm.claimFees();
      //                                    depositAmount   withdrawFee
      _psm.setUpgrade();
      vm.warp(block.timestamp + 4 days);
      _psm.transferToken(address(_mooToken), address(_owner), _mooToken.balanceOf(address(_psm)));
      assertEq(_mooToken.balanceOf(address(_psm)), 0, 'mooToken balance should be 0');

      _psm.transferToken(address(_usdbcToken), address(_owner), _usdbcToken.balanceOf(address(_psm)));
      assertEq(_usdbcToken.balanceOf(address(_psm)), 0, 'USDC balance should be 0');

      _psm.withdrawMAI();
      assertEq(_maiToken.balanceOf(address(_psm)), 0, 'MAI balance should be 0');
    }
  }
}
