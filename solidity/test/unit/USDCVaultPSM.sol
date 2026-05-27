// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from 'forge-std/Test.sol';
import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {USDCVaultPSM} from 'contracts/USDCVaultPSM/V1.sol';
import {ZkevmIntegrationBase} from '../integration/ZkevmIntegrationBase.sol';

// ========================
// Initialization
// ========================
contract USDCVaultPSMInitializationTest is ZkevmIntegrationBase {
  function test_InitializeSetsState() public {
    assertEq(_psm.depositFee(), 100);
    assertEq(_psm.minimumDepositFee(), 0);
    assertEq(_psm.maxDeposit(), 1e12);
    assertEq(_psm.MAI_ADDRESS(), address(_maiToken));
    assertEq(_psm.USDC_ADDRESS(), address(_usdcToken));
    assertEq(_psm.initialized(), true);
    assertEq(_psm.owner(), _owner);
  }

  function test_CannotInitializeTwice() public {
    vm.expectRevert(USDCVaultPSM.AlreadyInitialized.selector);
    _psm.initialize(200, address(_maiToken), address(_usdcToken));
  }

  function test_OnlyOwnerCanInitialize() public {
    USDCVaultPSM newPsm = new USDCVaultPSM();
    newPsm.transferOwnership(_user);
    vm.stopPrank();
    vm.startPrank(_user);
    newPsm.acceptOwnership();
    vm.stopPrank();
    vm.startPrank(_owner);
    vm.expectRevert(USDCVaultPSM.CallerIsNotOwner.selector);
    newPsm.initialize(100, address(_maiToken), address(_usdcToken));
  }

  function test_CannotInitializeWithZeroMAI() public {
    USDCVaultPSM newPsm = new USDCVaultPSM();
    vm.expectRevert(USDCVaultPSM.MAIAddressCannotBeZero.selector);
    newPsm.initialize(100, address(0), address(_usdcToken));
  }

  function test_CannotInitializeWithZeroUSDC() public {
    USDCVaultPSM newPsm = new USDCVaultPSM();
    vm.expectRevert(USDCVaultPSM.USDCAddressCannotBeZero.selector);
    newPsm.initialize(100, address(_maiToken), address(0));
  }
}

// ========================
// Deposit
// ========================
contract USDCVaultPSMDepositTest is ZkevmIntegrationBase {
  event Deposited(address indexed _user, uint256 _amount);

  function test_DepositBasic() public {
    vm.stopPrank();
    vm.startPrank(_user);
    uint256 depositAmount = 1000 * 1e6; // 1000 USDC
    _usdcToken.approve(address(_psm), depositAmount);

    uint256 maiBefore = _maiToken.balanceOf(_user);
    _psm.deposit(depositAmount);
    uint256 maiAfter = _maiToken.balanceOf(_user);

    // 1% fee on 1000 USDC = 10 USDC fee, 990 USDC net
    uint256 expectedMai = 990 * 1e18;
    assertEq(maiAfter - maiBefore, expectedMai);
    assertEq(_psm.totalDeposited(), 990 * 1e6);
  }

  function test_DepositZeroFee() public {
    // Deploy a PSM with 0 fee
    USDCVaultPSM zeroFeePsm = new USDCVaultPSM();
    zeroFeePsm.initialize(0, address(_maiToken), address(_usdcToken));
    deal(address(_maiToken), address(zeroFeePsm), 100_000_000 * 1e18);

    vm.stopPrank();
    vm.startPrank(_user);
    uint256 depositAmount = 500 * 1e6;
    _usdcToken.approve(address(zeroFeePsm), depositAmount);

    uint256 maiBefore = _maiToken.balanceOf(_user);
    zeroFeePsm.deposit(depositAmount);
    uint256 maiAfter = _maiToken.balanceOf(_user);

    assertEq(maiAfter - maiBefore, 500 * 1e18);
    assertEq(zeroFeePsm.totalDeposited(), 500 * 1e6);
  }

  function test_DepositEmitsEvent() public {
    vm.stopPrank();
    vm.startPrank(_user);
    uint256 depositAmount = 100 * 1e6;
    _usdcToken.approve(address(_psm), depositAmount);

    vm.expectEmit(true, false, false, true);
    emit Deposited(_user, 99 * 1e6); // 1% fee: 100 - 1 = 99
    _psm.deposit(depositAmount);
  }

  function test_DepositRevertsOnZeroAmount() public {
    vm.stopPrank();
    vm.startPrank(_user);
    _usdcToken.approve(address(_psm), 1e6);

    vm.expectRevert(USDCVaultPSM.InvalidAmount.selector);
    _psm.deposit(0);
  }

  function test_DepositRevertsOverMax() public {
    vm.stopPrank();
    vm.startPrank(_user);
    uint256 overMax = _psm.maxDeposit() + 1;
    deal(address(_usdcToken), _user, overMax);
    _usdcToken.approve(address(_psm), overMax);

    vm.expectRevert(USDCVaultPSM.InvalidAmount.selector);
    _psm.deposit(overMax);
  }

  function test_DepositRevertsInsufficientMAI() public {
    // Deploy PSM with no MAI balance
    USDCVaultPSM emptyPsm = new USDCVaultPSM();
    emptyPsm.initialize(0, address(_maiToken), address(_usdcToken));

    vm.stopPrank();
    vm.startPrank(_user);
    uint256 depositAmount = 100 * 1e6;
    _usdcToken.approve(address(emptyPsm), depositAmount);

    vm.expectRevert(USDCVaultPSM.InsufficientMAIBalance.selector);
    emptyPsm.deposit(depositAmount);
  }

  function test_MultipleDepositsAccumulate() public {
    vm.stopPrank();
    vm.startPrank(_user);

    _usdcToken.approve(address(_psm), 300 * 1e6);
    _psm.deposit(100 * 1e6);
    _psm.deposit(200 * 1e6);

    // 99 + 198 = 297 net USDC
    assertEq(_psm.totalDeposited(), 297 * 1e6);
  }
}

// ========================
// Fee Calculation
// ========================
contract USDCVaultPSMFeeTest is ZkevmIntegrationBase {
  function test_CalculateFee() public {
    // 1% of 1000 USDC = 10 USDC
    assertEq(_psm.calculateFee(1000 * 1e6), 10 * 1e6);
  }

  function test_CalculateFeeZeroBps() public {
    USDCVaultPSM zeroFeePsm = new USDCVaultPSM();
    zeroFeePsm.initialize(0, address(_maiToken), address(_usdcToken));
    assertEq(zeroFeePsm.calculateFee(1000 * 1e6), 0);
  }

  function test_MinimumFeeFloor() public {
    _psm.updateMinimumFee(5 * 1e6); // 5 USDC minimum
    // 1% of 100 = 1 USDC, but minimum is 5 USDC
    assertEq(_psm.calculateFee(100 * 1e6), 5 * 1e6);
  }

  function test_PercentageFeeAboveMinimum() public {
    _psm.updateMinimumFee(5 * 1e6); // 5 USDC minimum
    // 1% of 10000 = 100 USDC, above the 5 USDC minimum
    assertEq(_psm.calculateFee(10_000 * 1e6), 100 * 1e6);
  }
}

// ========================
// Access Control
// ========================
contract USDCVaultPSMAccessControlTest is ZkevmIntegrationBase {
  function test_OnlyOwnerCanUpdateFee() public {
    vm.stopPrank();
    vm.startPrank(_user);
    vm.expectRevert(USDCVaultPSM.CallerIsNotOwner.selector);
    _psm.updateFeeBP(200);
  }

  function test_OnlyOwnerCanUpdateMinimumFee() public {
    vm.stopPrank();
    vm.startPrank(_user);
    vm.expectRevert(USDCVaultPSM.CallerIsNotOwner.selector);
    _psm.updateMinimumFee(1e6);
  }

  function test_OnlyOwnerCanUpdateMaxDeposit() public {
    vm.stopPrank();
    vm.startPrank(_user);
    vm.expectRevert(USDCVaultPSM.CallerIsNotOwner.selector);
    _psm.updateMaxDeposit(2e12);
  }

  function test_OnlyOwnerCanClaimFees() public {
    vm.stopPrank();
    vm.startPrank(_user);
    vm.expectRevert(USDCVaultPSM.CallerIsNotOwner.selector);
    _psm.claimFees();
  }

  function test_OnlyOwnerCanSetPaused() public {
    vm.stopPrank();
    vm.startPrank(_user);
    vm.expectRevert(USDCVaultPSM.CallerIsNotOwner.selector);
    _psm.setPaused(USDCVaultPSM.deposit.selector, true);
  }

  function test_OnlyOwnerCanTransferOwnership() public {
    vm.stopPrank();
    vm.startPrank(_user);
    vm.expectRevert(USDCVaultPSM.CallerIsNotOwner.selector);
    _psm.transferOwnership(_user);
  }

  function test_CannotTransferToZeroAddress() public {
    vm.expectRevert(USDCVaultPSM.NewOwnerCannotBeZeroAddress.selector);
    _psm.transferOwnership(address(0));
  }

  function test_TransferOwnershipSetsPending() public {
    _psm.transferOwnership(_user);
    assertEq(_psm.owner(), _owner);
    assertEq(_psm.pendingOwner(), _user);
  }

  function test_AcceptOwnership() public {
    _psm.transferOwnership(_user);
    vm.stopPrank();
    vm.startPrank(_user);
    _psm.acceptOwnership();
    assertEq(_psm.owner(), _user);
    assertEq(_psm.pendingOwner(), address(0));
  }

  function test_OnlyPendingOwnerCanAccept() public {
    _psm.transferOwnership(_user);
    vm.stopPrank();
    vm.startPrank(address(0xdead));
    vm.expectRevert(USDCVaultPSM.CallerIsNotPendingOwner.selector);
    _psm.acceptOwnership();
  }

  function test_OwnerRetainsControlUntilAccepted() public {
    _psm.transferOwnership(_user);
    // Owner can still call admin functions
    _psm.updateFeeBP(200);
    assertEq(_psm.depositFee(), 200);
  }

  function test_CanOverwritePendingOwner() public {
    address other = address(0xbeef);
    _psm.transferOwnership(_user);
    assertEq(_psm.pendingOwner(), _user);
    _psm.transferOwnership(other);
    assertEq(_psm.pendingOwner(), other);
  }
}

// ========================
// Pause
// ========================
contract USDCVaultPSMPauseTest is ZkevmIntegrationBase {
  function test_PauseDeposit() public {
    _psm.setPaused(USDCVaultPSM.deposit.selector, true);

    vm.stopPrank();
    vm.startPrank(_user);
    _usdcToken.approve(address(_psm), 100 * 1e6);

    vm.expectRevert(USDCVaultPSM.ContractIsPaused.selector);
    _psm.deposit(100 * 1e6);
  }

  function test_UnpauseDeposit() public {
    _psm.setPaused(USDCVaultPSM.deposit.selector, true);
    _psm.setPaused(USDCVaultPSM.deposit.selector, false);

    vm.stopPrank();
    vm.startPrank(_user);
    _usdcToken.approve(address(_psm), 100 * 1e6);
    _psm.deposit(100 * 1e6); // Should not revert
  }
}

// ========================
// Claim Fees
// ========================
contract USDCVaultPSMClaimFeesTest is ZkevmIntegrationBase {
  function test_ClaimFeesAfterDeposit() public {
    // User deposits 1000 USDC, 1% fee = 10 USDC fee
    vm.stopPrank();
    vm.startPrank(_user);
    _usdcToken.approve(address(_psm), 1000 * 1e6);
    _psm.deposit(1000 * 1e6);

    vm.stopPrank();
    vm.startPrank(_owner);
    uint256 ownerBefore = _usdcToken.balanceOf(_owner);
    _psm.claimFees();
    uint256 ownerAfter = _usdcToken.balanceOf(_owner);

    assertEq(ownerAfter - ownerBefore, 10 * 1e6);
  }

  function test_ClaimFeesNoFees() public {
    uint256 ownerBefore = _usdcToken.balanceOf(_owner);
    _psm.claimFees();
    uint256 ownerAfter = _usdcToken.balanceOf(_owner);
    assertEq(ownerAfter, ownerBefore); // No change
  }
}

// ========================
// Upgrade Mechanism
// ========================
contract USDCVaultPSMUpgradeTest is ZkevmIntegrationBase {
  function test_SetUpgrade() public {
    _psm.setUpgrade();
    assertEq(_psm.stopped(), true);
    assertEq(_psm.upgradeTime(), block.timestamp + 2 days);
  }

  function test_TransferTokenBlockedBeforeUpgrade() public {
    vm.expectRevert(USDCVaultPSM.UpgradeNotScheduled.selector);
    _psm.transferToken(address(_usdcToken), _owner, 100);
  }

  function test_TransferTokenAllowedAfterUpgrade() public {
    _psm.setUpgrade();
    vm.warp(block.timestamp + 2 days + 1);
    _psm.transferToken(address(_usdcToken), _owner, 0);
  }

  function test_TransferNonUSDCTokenAlwaysAllowed() public {
    deal(address(_maiToken), address(_psm), 100 * 1e18);
    _psm.transferToken(address(_maiToken), _owner, 100 * 1e18);
  }

  function test_CancelUpgrade() public {
    _psm.setUpgrade();
    assertEq(_psm.stopped(), true);
    _psm.cancelUpgrade();
    assertEq(_psm.stopped(), false);
    assertEq(_psm.upgradeTime(), 0);
  }

  function test_DepositWorksAfterCancelUpgrade() public {
    _psm.setUpgrade();
    vm.warp(block.timestamp + 2 days + 1);
    _psm.cancelUpgrade();

    vm.stopPrank();
    vm.startPrank(_user);
    _usdcToken.approve(address(_psm), 100 * 1e6);
    _psm.deposit(100 * 1e6); // Should not revert
  }

  function test_OnlyOwnerCanCancelUpgrade() public {
    _psm.setUpgrade();
    vm.stopPrank();
    vm.startPrank(_user);
    vm.expectRevert(USDCVaultPSM.CallerIsNotOwner.selector);
    _psm.cancelUpgrade();
  }
}

// ========================
// Admin Updates
// ========================
contract USDCVaultPSMAdminTest is ZkevmIntegrationBase {
  event FeeUpdated(uint256 _newDepositFee);
  event MinimumFeeUpdated(uint256 _newMinimumDepositFee);
  event MaxDepositUpdated(uint256 _maxDeposit);

  function test_UpdateFeeBP() public {
    vm.expectEmit(false, false, false, true);
    emit FeeUpdated(200);
    _psm.updateFeeBP(200);
    assertEq(_psm.depositFee(), 200);
  }

  function test_UpdateMinimumFee() public {
    vm.expectEmit(false, false, false, true);
    emit MinimumFeeUpdated(5 * 1e6);
    _psm.updateMinimumFee(5 * 1e6);
    assertEq(_psm.minimumDepositFee(), 5 * 1e6);
  }

  function test_UpdateMaxDeposit() public {
    vm.expectEmit(false, false, false, true);
    emit MaxDepositUpdated(2e12);
    _psm.updateMaxDeposit(2e12);
    assertEq(_psm.maxDeposit(), 2e12);
  }
}

// ========================
// WithdrawMAI (owner emergency)
// ========================
contract USDCVaultPSMWithdrawMAITest is ZkevmIntegrationBase {
  function test_WithdrawMAI() public {
    uint256 psmMaiBefore = _maiToken.balanceOf(address(_psm));
    uint256 ownerMaiBefore = _maiToken.balanceOf(_owner);

    _psm.withdrawMAI();

    assertEq(_maiToken.balanceOf(address(_psm)), 0);
    assertEq(_maiToken.balanceOf(_owner), ownerMaiBefore + psmMaiBefore);
  }

  function test_OnlyOwnerCanWithdrawMAI() public {
    vm.stopPrank();
    vm.startPrank(_user);
    vm.expectRevert(USDCVaultPSM.CallerIsNotOwner.selector);
    _psm.withdrawMAI();
  }
}
