// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {Test} from 'forge-std/Test.sol';
import {IBeefy} from '../../interfaces/IBeefy.sol';
import {BeefyVaultPSM} from 'contracts/BeefyVaultDDW.sol';
import {console} from 'forge-std/console.sol';
import {BeefyIntegrationBase} from '../integration/BeefyIntegrationBase.sol';

/// @title RevertingBeefyMock
/// @notice IBeefy mock that reverts on withdrawAll — for testing evacuateVault failure path
contract RevertingBeefyMock {
  address public _want;
  uint8 public _decimals = 18;
  uint256 public totalSupply;
  mapping(address => uint256) public balanceOf;

  constructor(
    address want_
  ) {
    _want = want_;
  }

  function want() external view returns (address) {
    return _want;
  }

  function decimals() external view returns (uint8) {
    return _decimals;
  }

  function balance() external view returns (uint256) {
    return totalSupply;
  }

  function deposit(
    uint256 amount
  ) external {
    IERC20(_want).transferFrom(msg.sender, address(this), amount);
    balanceOf[msg.sender] += amount;
    totalSupply += amount;
  }

  function depositAll() external {
    uint256 amount = IERC20(_want).balanceOf(msg.sender);
    IERC20(_want).transferFrom(msg.sender, address(this), amount);
    balanceOf[msg.sender] += amount;
    totalSupply += amount;
  }

  function withdraw(
    uint256 shares
  ) external {
    balanceOf[msg.sender] -= shares;
    totalSupply -= shares;
    IERC20(_want).transfer(msg.sender, shares);
  }

  function withdrawAll() external pure {
    revert('VAULT_COMPROMISED');
  }

  function getPricePerFullShare() external pure returns (uint256) {
    return 1e18;
  }

  function approve(
    address,
    uint256
  ) external pure returns (bool) {
    return true;
  }
}

// ═══════════════════════════════════════════════════════════
//  Base Beefy PSM Evacuate & Sweep Tests (fork-based)
// ═══════════════════════════════════════════════════════════

contract BeefyVaultPSMEvacuateAndSweepTest is BeefyIntegrationBase {
  event VaultEvacuated(address indexed _caller, uint256 _sharesRedeemed);
  event Swept(address indexed _caller, uint256 _amount);
  event RefundClaimed(address indexed _user, uint256 _maiAmount);
  event GuardianUpdated(address _guardian, bool _enabled);
  event RedeemFailed(bytes _reason);

  address internal guardian = makeAddr('guardian');
  address internal random = makeAddr('random');

  function setUp() public override {
    super.setUp();

    // Re-init with 0% deposit / 30bps withdrawal (matching production)
    // Note: BeefyIntegrationBase already initializes with 100/100
    // We work with the existing initialization

    // Set up guardian
    _psm.setGuardian(guardian, true);
    vm.stopPrank();
  }

  function _depositAs(
    address user,
    uint256 amount
  ) internal {
    vm.startPrank(user);
    _usdbcToken.approve(address(_psm), amount);
    _psm.deposit(amount);
    vm.stopPrank();
  }

  function _scheduleWithdrawAs(
    address user,
    uint256 maiAmount
  ) internal {
    vm.startPrank(user);
    _maiToken.approve(address(_psm), maiAmount);
    _psm.scheduleWithdraw(maiAmount);
    vm.stopPrank();
  }

  // ═══════════════════════════════════════════════════════════
  //  Guardian management
  // ═══════════════════════════════════════════════════════════

  function test_setGuardian_ownerCanAdd() public {
    address newGuardian = makeAddr('newGuardian');
    vm.prank(_owner);
    _psm.setGuardian(newGuardian, true);
    assertTrue(_psm.guardians(newGuardian));
  }

  function test_setGuardian_ownerCanRemove() public {
    vm.prank(_owner);
    _psm.setGuardian(guardian, false);
    assertFalse(_psm.guardians(guardian));
  }

  function test_setGuardian_revertsForZeroAddress() public {
    vm.prank(_owner);
    vm.expectRevert(BeefyVaultPSM.GuardianCannotBeZeroAddress.selector);
    _psm.setGuardian(address(0), true);
  }

  function test_setGuardian_nonOwnerReverts() public {
    vm.prank(random);
    vm.expectRevert(BeefyVaultPSM.CallerIsNotOwner.selector);
    _psm.setGuardian(random, true);
  }

  // ═══════════════════════════════════════════════════════════
  //  evacuateVault tests
  // ═══════════════════════════════════════════════════════════

  function test_evacuateVault_happyPath() public {
    _depositAs(_user, 100_000 * 10 ** 6);

    IBeefy beefy = IBeefy(address(_mooToken));
    uint256 sharesBefore = beefy.balanceOf(address(_psm));
    assertGt(sharesBefore, 0, 'PSM should have vault shares');

    vm.prank(guardian);
    _psm.evacuateVault();

    assertTrue(_psm.evacuated(), 'Should be evacuated');
    assertTrue(_psm.stopped(), 'Should be stopped');
    assertGt(_psm.upgradeTime(), block.timestamp, 'Upgrade time should be in future');
    assertEq(beefy.balanceOf(address(_psm)), 0, 'Vault shares should be 0');
    assertGt(_usdbcToken.balanceOf(address(_psm)), 0, 'PSM should hold USDC');
  }

  function test_evacuateVault_ownerCanCall() public {
    _depositAs(_user, 10_000 * 10 ** 6);

    vm.prank(_owner);
    _psm.evacuateVault();

    assertTrue(_psm.evacuated());
  }

  function test_evacuateVault_guardianCanCall() public {
    _depositAs(_user, 10_000 * 10 ** 6);

    vm.prank(guardian);
    _psm.evacuateVault();

    assertTrue(_psm.evacuated());
  }

  function test_evacuateVault_randomAddressReverts() public {
    vm.prank(random);
    vm.expectRevert(BeefyVaultPSM.CallerIsNotGuardianOrOwner.selector);
    _psm.evacuateVault();
  }

  function test_evacuateVault_emitsEvent() public {
    _depositAs(_user, 10_000 * 10 ** 6);
    IBeefy beefy = IBeefy(address(_mooToken));
    uint256 sharesBefore = beefy.balanceOf(address(_psm));

    vm.expectEmit(true, false, false, true);
    emit VaultEvacuated(guardian, sharesBefore);

    vm.prank(guardian);
    _psm.evacuateVault();
  }

  function test_evacuateVault_freezesDeposits() public {
    _depositAs(_user, 10_000 * 10 ** 6);

    vm.prank(guardian);
    _psm.evacuateVault();

    vm.startPrank(_user);
    _usdbcToken.approve(address(_psm), 1000 * 10 ** 6);
    vm.expectRevert(BeefyVaultPSM.ContractIsPaused.selector);
    _psm.deposit(1000 * 10 ** 6);
    vm.stopPrank();
  }

  function test_evacuateVault_freezesScheduleWithdraw() public {
    _depositAs(_user, 10_000 * 10 ** 6);

    vm.prank(guardian);
    _psm.evacuateVault();

    vm.startPrank(_user);
    _maiToken.approve(address(_psm), 1000 * 10 ** 18);
    vm.expectRevert(BeefyVaultPSM.ContractIsPaused.selector);
    _psm.scheduleWithdraw(1000 * 10 ** 18);
    vm.stopPrank();
  }

  function test_evacuateVault_idempotent() public {
    _depositAs(_user, 10_000 * 10 ** 6);

    vm.prank(guardian);
    _psm.evacuateVault();

    // Second call should succeed without reverting
    vm.prank(_owner);
    _psm.evacuateVault();

    assertTrue(_psm.evacuated());
  }

  // ═══════════════════════════════════════════════════════════
  //  evacuateVault with reverting vault (try/catch)
  // ═══════════════════════════════════════════════════════════

  function test_evacuateVault_revertingVaultStillSetsEvacuated() public {
    // Deploy a reverting mock
    RevertingBeefyMock revertingVault = new RevertingBeefyMock(address(_usdbcToken));

    // Deploy a fresh PSM with the reverting vault
    vm.startPrank(_owner);
    BeefyVaultPSM revertPsm = new BeefyVaultPSM();
    deal(address(_maiToken), address(revertPsm), 10_000_000 * 10 ** 18);

    // Need to make the mock return proper decimals
    // The mock has decimals=18, underlying USDC=6, so decimalDifference=12 (correct)
    revertPsm.initialize(address(revertingVault), 100, 100);

    // Give the mock some balance to simulate shares
    deal(address(_usdbcToken), _owner, 1000 * 10 ** 6);
    _usdbcToken.approve(address(revertPsm), 1000 * 10 ** 6);
    revertPsm.deposit(1000 * 10 ** 6);

    // Now evacuate — withdrawAll() will revert, but evacuated should still be set
    vm.expectEmit(false, false, false, false);
    emit RedeemFailed('');

    revertPsm.evacuateVault();

    assertTrue(revertPsm.evacuated(), 'Should be evacuated even though vault reverted');
    assertTrue(revertPsm.stopped(), 'Should be stopped');
    vm.stopPrank();
  }

  // ═══════════════════════════════════════════════════════════
  //  claimRefund tests
  // ═══════════════════════════════════════════════════════════

  function test_claimRefund_happyPath() public {
    _depositAs(_user, 100_000 * 10 ** 6);

    // User schedules withdrawal
    uint256 withdrawMAI = 40_000 * 10 ** 18;
    deal(address(_maiToken), _user, withdrawMAI);
    _scheduleWithdrawAs(_user, withdrawMAI);

    assertEq(_psm.totalQueuedMAI(), withdrawMAI, 'totalQueuedMAI should track scheduled amount');

    // Evacuate
    vm.prank(guardian);
    _psm.evacuateVault();

    // User claims refund
    uint256 maiBalBefore = _maiToken.balanceOf(_user);
    vm.prank(_user);
    _psm.claimRefund();

    assertEq(_maiToken.balanceOf(_user), maiBalBefore + withdrawMAI, 'User should get MAI back');
    assertEq(_psm.scheduledWithdrawalAmount(_user), 0, 'Scheduled amount should be cleared');
    assertEq(_psm.withdrawalEpoch(_user), 0, 'Withdrawal epoch should be cleared');
    assertEq(_psm.totalQueuedMAI(), 0, 'totalQueuedMAI should be 0');
  }

  function test_claimRefund_revertsWhenNotEvacuated() public {
    vm.prank(_user);
    vm.expectRevert(BeefyVaultPSM.NotEvacuated.selector);
    _psm.claimRefund();
  }

  function test_claimRefund_revertsWhenNoScheduledWithdrawal() public {
    vm.prank(guardian);
    _psm.evacuateVault();

    vm.prank(_user);
    vm.expectRevert(BeefyVaultPSM.NoWithdrawalScheduled.selector);
    _psm.claimRefund();
  }

  function test_claimRefund_nonRoundAmount() public {
    _depositAs(_user, 100_000 * 10 ** 6);

    // Use non-round amount to catch precision bugs
    uint256 withdrawMAI = 40_000 * 10 ** 18 + 1;
    deal(address(_maiToken), _user, withdrawMAI);
    _scheduleWithdrawAs(_user, withdrawMAI);

    vm.prank(guardian);
    _psm.evacuateVault();

    uint256 maiBalBefore = _maiToken.balanceOf(_user);
    vm.prank(_user);
    _psm.claimRefund();

    assertEq(_maiToken.balanceOf(_user), maiBalBefore + withdrawMAI, 'Should refund exact MAI amount');
  }

  // ═══════════════════════════════════════════════════════════
  //  sweep tests
  // ═══════════════════════════════════════════════════════════

  function test_sweep_happyPath() public {
    // Send USDC directly to PSM (simulating migration)
    uint256 sweepAmount = 50_000 * 10 ** 6;
    deal(address(_usdbcToken), address(_psm), sweepAmount);

    uint256 liquidityBefore = _psm.totalStableLiquidity();
    IBeefy beefy = IBeefy(address(_mooToken));
    uint256 sharesBefore = beefy.balanceOf(address(_psm));

    vm.prank(_owner);
    _psm.sweep();

    assertEq(_psm.totalStableLiquidity(), liquidityBefore + sweepAmount, 'Liquidity should increase');
    assertGt(beefy.balanceOf(address(_psm)), sharesBefore, 'Shares should increase');
    assertEq(_usdbcToken.balanceOf(address(_psm)), 0, 'USDC should be deposited into vault');
  }

  function test_sweep_revertsWhenEvacuated() public {
    vm.prank(guardian);
    _psm.evacuateVault();

    vm.prank(_owner);
    vm.expectRevert(BeefyVaultPSM.ContractIsPaused.selector);
    _psm.sweep();
  }

  function test_sweep_revertsWhenNoBalance() public {
    vm.prank(_owner);
    vm.expectRevert(BeefyVaultPSM.InvalidAmount.selector);
    _psm.sweep();
  }

  function test_sweep_nonOwnerReverts() public {
    deal(address(_usdbcToken), address(_psm), 1000 * 10 ** 6);

    vm.prank(random);
    vm.expectRevert(BeefyVaultPSM.CallerIsNotOwner.selector);
    _psm.sweep();
  }

  function test_sweep_emitsEvent() public {
    uint256 sweepAmount = 10_000 * 10 ** 6;
    deal(address(_usdbcToken), address(_psm), sweepAmount);

    vm.expectEmit(true, false, false, true);
    emit Swept(_owner, sweepAmount);

    vm.prank(_owner);
    _psm.sweep();
  }

  // ═══════════════════════════════════════════════════════════
  //  withdrawMAI post-evacuation protection
  // ═══════════════════════════════════════════════════════════

  function test_withdrawMAI_protectsRefundsPostEvacuation() public {
    _depositAs(_user, 100_000 * 10 ** 6);

    uint256 withdrawMAI = 40_000 * 10 ** 18;
    deal(address(_maiToken), _user, withdrawMAI);
    _scheduleWithdrawAs(_user, withdrawMAI);

    vm.prank(guardian);
    _psm.evacuateVault();

    // Owner tries to withdraw MAI — should only get excess above totalQueuedMAI
    uint256 psmMaiBefore = _maiToken.balanceOf(address(_psm));
    uint256 ownerMaiBefore = _maiToken.balanceOf(_owner);

    vm.prank(_owner);
    _psm.withdrawMAI();

    uint256 ownerMaiAfter = _maiToken.balanceOf(_owner);
    uint256 expectedAvailable = psmMaiBefore > withdrawMAI ? psmMaiBefore - withdrawMAI : 0;
    assertEq(ownerMaiAfter - ownerMaiBefore, expectedAvailable, 'Owner should only get non-queued MAI');

    // User can still claim refund
    uint256 userMaiBefore = _maiToken.balanceOf(_user);
    vm.prank(_user);
    _psm.claimRefund();
    assertEq(_maiToken.balanceOf(_user), userMaiBefore + withdrawMAI, 'User should still get full refund');
  }

  function test_withdrawMAI_transfersAllExcessPreEvacuationWhenNothingQueued() public {
    uint256 maiBalance = _maiToken.balanceOf(address(_psm));

    uint256 ownerBefore = _maiToken.balanceOf(_owner);
    vm.prank(_owner);
    _psm.withdrawMAI();

    assertEq(
      _maiToken.balanceOf(_owner), ownerBefore + maiBalance, 'Owner should get all excess MAI when nothing is queued'
    );
    assertEq(_maiToken.balanceOf(address(_psm)), 0, 'PSM should have no MAI left when nothing is queued');
  }

  function test_withdrawMAI_protectsQueuedMAIPreEvacuation() public {
    _depositAs(_user, 100_000 * 10 ** 6);

    uint256 withdrawMAI = 40_000 * 10 ** 18;
    deal(address(_maiToken), _user, withdrawMAI);
    _scheduleWithdrawAs(_user, withdrawMAI);

    uint256 psmMaiBefore = _maiToken.balanceOf(address(_psm));
    uint256 ownerBefore = _maiToken.balanceOf(_owner);
    vm.prank(_owner);
    _psm.withdrawMAI();

    assertEq(_maiToken.balanceOf(address(_psm)), withdrawMAI, 'PSM should retain queued MAI pre-evacuation');
    assertEq(
      _maiToken.balanceOf(_owner) - ownerBefore,
      psmMaiBefore - withdrawMAI,
      'Owner should only receive MAI in excess of the queued reserve'
    );

    vm.prank(guardian);
    _psm.evacuateVault();

    uint256 userMaiBefore = _maiToken.balanceOf(_user);
    vm.prank(_user);
    _psm.claimRefund();

    assertEq(
      _maiToken.balanceOf(_user), userMaiBefore + withdrawMAI, 'User should still be able to claim the full refund'
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  transferToken post-evacuation protection
  // ═══════════════════════════════════════════════════════════

  function test_transferToken_blocksUnderlyingPostEvacuation() public {
    _depositAs(_user, 10_000 * 10 ** 6);

    vm.prank(guardian);
    _psm.evacuateVault();

    uint256 usdcInPsm = _usdbcToken.balanceOf(address(_psm));
    assertGt(usdcInPsm, 0, 'PSM should hold USDC post-evacuation');

    vm.prank(_owner);
    vm.expectRevert(BeefyVaultPSM.UpgradeNotScheduled.selector);
    _psm.transferToken(address(_usdbcToken), _owner, usdcInPsm);
  }

  function test_transferToken_allowsUnderlyingAfterUpgradeTime() public {
    _depositAs(_user, 10_000 * 10 ** 6);

    vm.prank(guardian);
    _psm.evacuateVault();

    // Warp past upgrade time
    vm.warp(_psm.upgradeTime() + 1);

    uint256 usdcInPsm = _usdbcToken.balanceOf(address(_psm));
    uint256 ownerBefore = _usdbcToken.balanceOf(_owner);
    vm.prank(_owner);
    _psm.transferToken(address(_usdbcToken), _owner, usdcInPsm);

    assertEq(_usdbcToken.balanceOf(_owner) - ownerBefore, usdcInPsm, 'Owner should receive USDC after upgrade time');
  }

  function test_transferToken_limitsMAIPostEvacuation() public {
    _depositAs(_user, 100_000 * 10 ** 6);

    uint256 withdrawMAI = 40_000 * 10 ** 18;
    deal(address(_maiToken), _user, withdrawMAI);
    _scheduleWithdrawAs(_user, withdrawMAI);

    vm.prank(guardian);
    _psm.evacuateVault();

    // Trying to transfer more MAI than available (above totalQueuedMAI) should revert
    uint256 psmMaiBalance = _maiToken.balanceOf(address(_psm));
    vm.prank(_owner);
    vm.expectRevert(BeefyVaultPSM.NotEnoughLiquidity.selector);
    _psm.transferToken(address(_maiToken), _owner, psmMaiBalance);
  }

  function test_transferToken_protectsQueuedMAIPreEvacuation() public {
    _depositAs(_user, 100_000 * 10 ** 6);

    uint256 withdrawMAI = 40_000 * 10 ** 18;
    deal(address(_maiToken), _user, withdrawMAI);
    _scheduleWithdrawAs(_user, withdrawMAI);

    uint256 psmMaiBalance = _maiToken.balanceOf(address(_psm));
    uint256 available = psmMaiBalance - withdrawMAI;

    vm.prank(_owner);
    vm.expectRevert(BeefyVaultPSM.NotEnoughLiquidity.selector);
    _psm.transferToken(address(_maiToken), _owner, psmMaiBalance);

    uint256 ownerBefore = _maiToken.balanceOf(_owner);
    vm.prank(_owner);
    _psm.transferToken(address(_maiToken), _owner, available);

    assertEq(_maiToken.balanceOf(_owner) - ownerBefore, available, 'Owner should only receive non-queued MAI');
    assertEq(_maiToken.balanceOf(address(_psm)), withdrawMAI, 'Queued MAI must remain in the PSM');
  }

  function test_preEvacuationQueuedMAIDrainAttemptStillAllowsRefundAfterEvacuation() public {
    uint256 sweepAmount = 50_000 * 10 ** 6;
    deal(address(_usdbcToken), address(_psm), sweepAmount);

    vm.prank(_owner);
    _psm.sweep();

    uint256 withdrawMAI = 10_000 * 10 ** 18;
    deal(address(_maiToken), _user, withdrawMAI);
    _scheduleWithdrawAs(_user, withdrawMAI);

    vm.prank(_owner);
    _psm.withdrawMAI();

    assertEq(
      _maiToken.balanceOf(address(_psm)), withdrawMAI, 'Pre-evacuation drain attempt must leave queued MAI intact'
    );

    vm.prank(guardian);
    _psm.evacuateVault();

    uint256 userMaiBefore = _maiToken.balanceOf(_user);
    vm.prank(_user);
    _psm.claimRefund();

    assertEq(_maiToken.balanceOf(_user), userMaiBefore + withdrawMAI, 'Refund should still succeed after evacuation');
  }

  // ═══════════════════════════════════════════════════════════
  //  claimFees post-evacuation guard
  // ═══════════════════════════════════════════════════════════

  function test_claimFees_noOpPostEvacuation() public {
    _depositAs(_user, 10_000 * 10 ** 6);

    vm.prank(guardian);
    _psm.evacuateVault();

    uint256 ownerUsdcBefore = _usdbcToken.balanceOf(_owner);
    vm.prank(_owner);
    _psm.claimFees(); // Should return without doing anything

    assertEq(_usdbcToken.balanceOf(_owner), ownerUsdcBefore, 'claimFees should be no-op post-evacuation');
  }

  // ═══════════════════════════════════════════════════════════
  //  totalQueuedMAI bookkeeping
  // ═══════════════════════════════════════════════════════════

  function test_totalQueuedMAI_trackedOnSchedule() public {
    _depositAs(_user, 100_000 * 10 ** 6);

    uint256 withdrawMAI = 40_000 * 10 ** 18;
    deal(address(_maiToken), _user, withdrawMAI);
    _scheduleWithdrawAs(_user, withdrawMAI);

    assertEq(_psm.totalQueuedMAI(), withdrawMAI);
  }

  function test_totalQueuedMAI_decrementedOnWithdraw() public {
    _depositAs(_user, 100_000 * 10 ** 6);

    uint256 withdrawMAI = 40_000 * 10 ** 18;
    deal(address(_maiToken), _user, withdrawMAI);
    _scheduleWithdrawAs(_user, withdrawMAI);

    assertEq(_psm.totalQueuedMAI(), withdrawMAI);

    // Warp past epoch and withdraw
    vm.warp(block.timestamp + 4 days);
    vm.prank(_user);
    _psm.withdraw();

    assertEq(_psm.totalQueuedMAI(), 0, 'totalQueuedMAI should be 0 after withdrawal');
  }

  // ═══════════════════════════════════════════════════════════
  //  Dust withdrawal rejection
  // ═══════════════════════════════════════════════════════════

  function test_scheduleWithdraw_rejectsDustAmount() public {
    _depositAs(_user, 100_000 * 10 ** 6);

    // Amount that truncates to 0 USDC after division by 1e12
    uint256 dustMAI = 2;
    deal(address(_maiToken), _user, dustMAI);

    vm.startPrank(_user);
    _maiToken.approve(address(_psm), dustMAI);
    vm.expectRevert(BeefyVaultPSM.InvalidAmountAfterFee.selector);
    _psm.scheduleWithdraw(dustMAI);
    vm.stopPrank();
  }

  // ═══════════════════════════════════════════════════════════
  //  withdraw blocked post-evacuation
  // ═══════════════════════════════════════════════════════════

  function test_withdraw_blockedPostEvacuation() public {
    _depositAs(_user, 100_000 * 10 ** 6);

    uint256 withdrawMAI = 40_000 * 10 ** 18;
    deal(address(_maiToken), _user, withdrawMAI);
    _scheduleWithdrawAs(_user, withdrawMAI);

    // Warp past 3-day epoch
    vm.warp(block.timestamp + 3 days);

    // Evacuate
    vm.prank(guardian);
    _psm.evacuateVault();

    // withdraw() should be blocked by pausable modifier post-evacuation
    vm.prank(_user);
    vm.expectRevert(BeefyVaultPSM.ContractIsPaused.selector);
    _psm.withdraw();
  }

  // ═══════════════════════════════════════════════════════════
  //  forceSettle tests
  // ═══════════════════════════════════════════════════════════

  function test_forceSettle_happyPath() public {
    _depositAs(_user, 100_000 * 10 ** 6);

    uint256 withdrawMAI = 40_000 * 10 ** 18;
    deal(address(_maiToken), _user, withdrawMAI);
    _scheduleWithdrawAs(_user, withdrawMAI);

    // Evacuate
    vm.prank(guardian);
    _psm.evacuateVault();

    // Warp past 30-day settlement timeout
    vm.warp(block.timestamp + 30 days);

    uint256 userMaiBefore = _maiToken.balanceOf(_user);
    vm.prank(_owner);
    _psm.forceSettle(_user);

    assertEq(_maiToken.balanceOf(_user), userMaiBefore + withdrawMAI, 'User should receive MAI via forceSettle');
    assertEq(_psm.scheduledWithdrawalAmount(_user), 0, 'Scheduled amount should be cleared');
    assertEq(_psm.withdrawalEpoch(_user), 0, 'Withdrawal epoch should be cleared');
  }

  function test_forceSettle_revertsBeforeTimeout() public {
    _depositAs(_user, 100_000 * 10 ** 6);

    uint256 withdrawMAI = 40_000 * 10 ** 18;
    deal(address(_maiToken), _user, withdrawMAI);
    _scheduleWithdrawAs(_user, withdrawMAI);

    // Evacuate
    vm.prank(guardian);
    _psm.evacuateVault();

    // Try forceSettle immediately — should revert
    vm.prank(_owner);
    vm.expectRevert(BeefyVaultPSM.SettlementTooEarly.selector);
    _psm.forceSettle(_user);
  }

  function test_forceSettle_revertsWhenNotEvacuated() public {
    vm.prank(_owner);
    vm.expectRevert(BeefyVaultPSM.NotEvacuated.selector);
    _psm.forceSettle(_user);
  }

  function test_forceSettle_clearsQueue() public {
    _depositAs(_user, 100_000 * 10 ** 6);

    uint256 withdrawMAI = 40_000 * 10 ** 18;
    deal(address(_maiToken), _user, withdrawMAI);
    _scheduleWithdrawAs(_user, withdrawMAI);

    uint256 queuedLiqBefore = _psm.totalQueuedLiquidity();
    uint256 queuedMaiBefore = _psm.totalQueuedMAI();
    assertGt(queuedLiqBefore, 0, 'Should have queued liquidity');
    assertGt(queuedMaiBefore, 0, 'Should have queued MAI');

    // Evacuate
    vm.prank(guardian);
    _psm.evacuateVault();

    // Warp past 30-day settlement timeout
    vm.warp(block.timestamp + 30 days);

    vm.prank(_owner);
    _psm.forceSettle(_user);

    assertEq(_psm.totalQueuedLiquidity(), 0, 'totalQueuedLiquidity should be 0 after forceSettle');
    assertEq(_psm.totalQueuedMAI(), 0, 'totalQueuedMAI should be 0 after forceSettle');
  }

  // ═══════════════════════════════════════════════════════════
  //  transferToken — owner gets ALL USDC after evacuation
  // ═══════════════════════════════════════════════════════════

  function test_transferToken_ownerGetsAllUsdcAfterEvacuation() public {
    _depositAs(_user, 100_000 * 10 ** 6);

    uint256 withdrawMAI = 40_000 * 10 ** 18;
    deal(address(_maiToken), _user, withdrawMAI);
    _scheduleWithdrawAs(_user, withdrawMAI);

    // Evacuate — all vault shares redeemed to USDC
    vm.prank(guardian);
    _psm.evacuateVault();

    // Warp past upgradeTime
    vm.warp(_psm.upgradeTime() + 1);

    uint256 usdcInPsm = _usdbcToken.balanceOf(address(_psm));
    assertGt(usdcInPsm, 0, 'PSM should hold USDC post-evacuation');

    // Owner should be able to transfer ALL USDC — no reservation needed
    uint256 ownerBefore = _usdbcToken.balanceOf(_owner);
    vm.prank(_owner);
    _psm.transferToken(address(_usdbcToken), _owner, usdcInPsm);

    assertEq(_usdbcToken.balanceOf(_owner) - ownerBefore, usdcInPsm, 'Owner should receive ALL USDC (no reservation)');
    assertEq(_usdbcToken.balanceOf(address(_psm)), 0, 'PSM should have no USDC left');
  }
}
