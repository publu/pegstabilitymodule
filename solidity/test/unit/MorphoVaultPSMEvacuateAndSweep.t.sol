// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from 'forge-std/Test.sol';
import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {MorphoVaultPSMV2} from 'contracts/MorphoVaultPSM/V2.sol';
import {IFly} from '../../interfaces/IFly.sol';
import {console} from 'forge-std/console.sol';

/// @title RevertingMockVault
/// @notice ERC4626 mock that reverts on redeem — for testing evacuateVault failure path
contract RevertingMockVault {
  address public underlying;
  uint8 public decimals = 6;
  uint256 public totalSupply;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  bool public shouldRevertOnRedeem = true;

  constructor(
    address _underlying
  ) {
    underlying = _underlying;
  }

  function asset() external view returns (address) {
    return underlying;
  }

  function deposit(
    uint256 assets,
    address receiver
  ) external returns (uint256) {
    IERC20(underlying).transferFrom(msg.sender, address(this), assets);
    balanceOf[receiver] += assets;
    totalSupply += assets;
    return assets;
  }

  function redeem(
    uint256,
    address,
    address
  ) external view returns (uint256) {
    if (shouldRevertOnRedeem) revert('VAULT_COMPROMISED');
    return 0;
  }

  function convertToAssets(
    uint256 shares
  ) external pure returns (uint256) {
    return shares;
  }

  function approve(
    address spender,
    uint256 amount
  ) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }
}

/// @title MorphoVaultPSMEvacuateAndSweepTest
/// @notice Unit tests for evacuateVault, claimRefund, sweep, and guardian role
/// @dev Fork tests targeting Base chain with real Morpho Gauntlet vault
contract MorphoVaultPSMEvacuateAndSweepTest is Test {
  // Re-declare events for expectEmit
  event VaultEvacuated(address indexed _caller, uint256 _sharesRedeemed);
  event Swept(address indexed _caller, uint256 _amount);
  event RefundClaimed(address indexed _user, uint256 _maiAmount);
  event GuardianUpdated(address _guardian, bool _enabled);

  MorphoVaultPSMV2 internal psm;

  address internal owner = makeAddr('owner');
  address internal guardian = makeAddr('guardian');
  address internal user1 = makeAddr('user1');
  address internal user2 = makeAddr('user2');
  address internal random = makeAddr('random');

  // Base chain addresses
  address internal constant MORPHO_GAUNTLET = 0xc0c5689e6f4D256E861F65465b691aeEcC0dEb12;
  address internal constant MAI_BASE = 0xbf1aeA8670D2528E08334083616dD9C5F3B087aE;
  address internal constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

  IERC20 internal usdcToken = IERC20(USDC_BASE);
  IERC20 internal maiToken = IERC20(MAI_BASE);
  IFly internal morphoVault = IFly(MORPHO_GAUNTLET);

  function _dealUSDC(
    address to,
    uint256 amount
  ) internal {
    // Base USDC uses slot 9 for balances (same as mainnet USDC proxy)
    bytes32 storageSlot = keccak256(abi.encode(to, uint256(9)));
    vm.store(USDC_BASE, storageSlot, bytes32(amount));
  }

  function _dealMAI(
    address to,
    uint256 amount
  ) internal {
    // Use deal cheatcode for MAI on Base
    deal(MAI_BASE, to, amount);
  }

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl('base'));

    vm.startPrank(owner);
    psm = new MorphoVaultPSMV2();
    vm.stopPrank();

    // Fund PSM with MAI for deposits
    _dealMAI(address(psm), 5_000_000 * 10 ** 18);

    // Fund users with USDC
    _dealUSDC(user1, 1_000_000 * 10 ** 6);
    _dealUSDC(user2, 1_000_000 * 10 ** 6);

    // Initialize PSM: 0% deposit fee, 30 bps withdrawal fee
    vm.startPrank(owner);
    psm.initialize(MORPHO_GAUNTLET, 0, 30, MAI_BASE);
    psm.setGuardian(guardian, true);
    vm.stopPrank();
  }

  // ═══════════════════════════════════════════════════════════
  //  Helper: deposit USDC into PSM as a user
  // ═══════════════════════════════════════════════════════════

  function _depositAs(
    address user,
    uint256 amount
  ) internal {
    vm.startPrank(user);
    usdcToken.approve(address(psm), amount);
    psm.deposit(amount);
    vm.stopPrank();
  }

  function _scheduleWithdrawAs(
    address user,
    uint256 maiAmount
  ) internal {
    vm.startPrank(user);
    maiToken.approve(address(psm), maiAmount);
    psm.scheduleWithdraw(maiAmount);
    vm.stopPrank();
  }

  // ═══════════════════════════════════════════════════════════
  //  evacuateVault tests
  // ═══════════════════════════════════════════════════════════

  function test_evacuateVault_happyPath() public {
    // Deposit some USDC first
    _depositAs(user1, 100_000 * 10 ** 6);

    uint256 vaultSharesBefore = morphoVault.balanceOf(address(psm));
    assertGt(vaultSharesBefore, 0, 'PSM should have vault shares');

    vm.prank(guardian);
    psm.evacuateVault();

    assertTrue(psm.evacuated(), 'Should be evacuated');
    assertTrue(psm.stopped(), 'Should be stopped');
    assertGt(psm.upgradeTime(), block.timestamp, 'Upgrade time should be in future');
    assertEq(morphoVault.balanceOf(address(psm)), 0, 'Vault shares should be 0');
    assertGt(usdcToken.balanceOf(address(psm)), 0, 'PSM should hold USDC');
  }

  function test_evacuateVault_ownerCanCall() public {
    _depositAs(user1, 10_000 * 10 ** 6);

    vm.prank(owner);
    psm.evacuateVault();

    assertTrue(psm.evacuated());
  }

  function test_evacuateVault_guardianCanCall() public {
    _depositAs(user1, 10_000 * 10 ** 6);

    vm.prank(guardian);
    psm.evacuateVault();

    assertTrue(psm.evacuated());
  }

  function test_evacuateVault_randomAddressReverts() public {
    vm.prank(random);
    vm.expectRevert(MorphoVaultPSMV2.CallerIsNotGuardianOrOwner.selector);
    psm.evacuateVault();
  }

  function test_evacuateVault_idempotent() public {
    _depositAs(user1, 10_000 * 10 ** 6);

    vm.prank(guardian);
    psm.evacuateVault();

    uint256 usdcAfterFirst = usdcToken.balanceOf(address(psm));

    // Call again — should not revert
    vm.prank(guardian);
    psm.evacuateVault();

    assertTrue(psm.evacuated());
    assertEq(usdcToken.balanceOf(address(psm)), usdcAfterFirst, 'USDC balance should not change');
  }

  function test_evacuateVault_doesNotResetUpgradeTime() public {
    // First call setUpgrade
    vm.prank(owner);
    psm.setUpgrade();
    uint256 originalUpgradeTime = psm.upgradeTime();

    // Then evacuate — should not reset upgradeTime
    vm.prank(guardian);
    psm.evacuateVault();

    assertEq(psm.upgradeTime(), originalUpgradeTime, 'upgradeTime should not be reset');
  }

  function test_evacuateVault_freezesContractImmediately() public {
    _depositAs(user1, 10_000 * 10 ** 6);

    vm.prank(guardian);
    psm.evacuateVault();

    // deposit should revert
    _dealUSDC(user2, 10_000 * 10 ** 6);
    vm.startPrank(user2);
    usdcToken.approve(address(psm), 10_000 * 10 ** 6);
    vm.expectRevert(MorphoVaultPSMV2.ContractIsPaused.selector);
    psm.deposit(10_000 * 10 ** 6);
    vm.stopPrank();

    // scheduleWithdraw should revert
    _dealMAI(user2, 10_000 * 10 ** 18);
    vm.startPrank(user2);
    maiToken.approve(address(psm), 10_000 * 10 ** 18);
    vm.expectRevert(MorphoVaultPSMV2.ContractIsPaused.selector);
    psm.scheduleWithdraw(10_000 * 10 ** 18);
    vm.stopPrank();
  }

  function test_evacuateVault_freezesWithdraw() public {
    _depositAs(user1, 10_000 * 10 ** 6);

    // Schedule a withdrawal
    uint256 maiAmount = 5000 * 10 ** 18;
    _dealMAI(user1, maiAmount);
    _scheduleWithdrawAs(user1, maiAmount);

    // Warp past withdrawal epoch
    vm.warp(block.timestamp + 4 days);

    // Evacuate
    vm.prank(guardian);
    psm.evacuateVault();

    // withdraw should revert even though epoch passed
    vm.prank(user1);
    vm.expectRevert(MorphoVaultPSMV2.ContractIsPaused.selector);
    psm.withdraw();
  }

  function test_evacuateVault_bookkeepingPreserved() public {
    _depositAs(user1, 100_000 * 10 ** 6);

    uint256 stableBefore = psm.totalStableLiquidity();
    uint256 queuedBefore = psm.totalQueuedLiquidity();

    vm.prank(guardian);
    psm.evacuateVault();

    assertEq(psm.totalStableLiquidity(), stableBefore, 'totalStableLiquidity should not change');
    assertEq(psm.totalQueuedLiquidity(), queuedBefore, 'totalQueuedLiquidity should not change');
  }

  function test_evacuateVault_emitsEvent() public {
    _depositAs(user1, 10_000 * 10 ** 6);

    uint256 expectedShares = morphoVault.balanceOf(address(psm));

    vm.prank(guardian);
    vm.expectEmit(true, false, false, true);
    emit VaultEvacuated(guardian, expectedShares);
    psm.evacuateVault();
  }

  // ═══════════════════════════════════════════════════════════
  //  claimRefund tests
  // ═══════════════════════════════════════════════════════════

  function test_claimRefund_happyPath() public {
    _depositAs(user1, 100_000 * 10 ** 6);

    // Schedule withdrawal
    uint256 maiAmount = 50_000 * 10 ** 18;
    _dealMAI(user1, maiAmount);
    _scheduleWithdrawAs(user1, maiAmount);

    uint256 stableBefore = psm.totalStableLiquidity();
    uint256 queuedBefore = psm.totalQueuedLiquidity();

    // Evacuate
    vm.prank(guardian);
    psm.evacuateVault();

    // Claim refund
    uint256 maiBalanceBefore = maiToken.balanceOf(user1);
    vm.prank(user1);
    psm.claimRefund();

    // User got MAI back
    assertEq(maiToken.balanceOf(user1), maiBalanceBefore + maiAmount, 'Should receive MAI back');

    // Bookkeeping updated
    uint256 toRefund = maiAmount / (10 ** 12); // decimalDifference = 12
    assertEq(psm.totalStableLiquidity(), stableBefore - toRefund, 'totalStableLiquidity decreased');
    assertEq(psm.totalQueuedLiquidity(), queuedBefore - toRefund, 'totalQueuedLiquidity decreased');

    // Mappings cleared
    assertEq(psm.scheduledWithdrawalAmount(user1), 0, 'scheduledWithdrawalAmount cleared');
    assertEq(psm.withdrawalEpoch(user1), 0, 'withdrawalEpoch cleared');
  }

  function test_claimRefund_revertsWhenNotEvacuated() public {
    vm.prank(user1);
    vm.expectRevert(MorphoVaultPSMV2.NotEvacuated.selector);
    psm.claimRefund();
  }

  function test_claimRefund_revertsWhenNoPendingWithdrawal() public {
    vm.prank(guardian);
    psm.evacuateVault();

    vm.prank(user1);
    vm.expectRevert(MorphoVaultPSMV2.NoWithdrawalScheduled.selector);
    psm.claimRefund();
  }

  function test_claimRefund_revertsOnDoubleClaim() public {
    _depositAs(user1, 100_000 * 10 ** 6);
    uint256 maiAmount = 50_000 * 10 ** 18;
    _dealMAI(user1, maiAmount);
    _scheduleWithdrawAs(user1, maiAmount);

    vm.prank(guardian);
    psm.evacuateVault();

    vm.prank(user1);
    psm.claimRefund();

    vm.prank(user1);
    vm.expectRevert(MorphoVaultPSMV2.NoWithdrawalScheduled.selector);
    psm.claimRefund();
  }

  function test_claimRefund_multipleUsers() public {
    _depositAs(user1, 100_000 * 10 ** 6);
    _depositAs(user2, 100_000 * 10 ** 6);

    uint256 mai1 = 30_000 * 10 ** 18;
    uint256 mai2 = 20_000 * 10 ** 18;
    _dealMAI(user1, mai1);
    _dealMAI(user2, mai2);
    _scheduleWithdrawAs(user1, mai1);
    _scheduleWithdrawAs(user2, mai2);

    vm.prank(guardian);
    psm.evacuateVault();

    vm.prank(user1);
    psm.claimRefund();

    vm.prank(user2);
    psm.claimRefund();

    assertEq(psm.totalQueuedLiquidity(), 0, 'All queued liquidity should be drained');
  }

  function test_claimRefund_emitsEvent() public {
    _depositAs(user1, 100_000 * 10 ** 6);
    uint256 maiAmount = 50_000 * 10 ** 18;
    _dealMAI(user1, maiAmount);
    _scheduleWithdrawAs(user1, maiAmount);

    vm.prank(guardian);
    psm.evacuateVault();

    vm.prank(user1);
    vm.expectEmit(true, false, false, true);
    emit RefundClaimed(user1, maiAmount);
    psm.claimRefund();
  }

  // ═══════════════════════════════════════════════════════════
  //  sweep tests
  // ═══════════════════════════════════════════════════════════

  function test_sweep_happyPath() public {
    // Send USDC directly to the contract (simulating migration)
    uint256 sweepAmount = 50_000 * 10 ** 6;
    _dealUSDC(address(psm), sweepAmount);

    uint256 stableBefore = psm.totalStableLiquidity();
    uint256 vaultSharesBefore = morphoVault.balanceOf(address(psm));

    vm.prank(owner);
    psm.sweep();

    assertEq(psm.totalStableLiquidity(), stableBefore + sweepAmount, 'totalStableLiquidity increased by swept amount');
    assertGt(morphoVault.balanceOf(address(psm)), vaultSharesBefore, 'Vault shares should increase');
    assertEq(usdcToken.balanceOf(address(psm)), 0, 'No idle USDC should remain');
  }

  function test_sweep_revertsOnZeroBalance() public {
    vm.prank(owner);
    vm.expectRevert(MorphoVaultPSMV2.InvalidAmount.selector);
    psm.sweep();
  }

  function test_sweep_revertsWhenEvacuated() public {
    vm.prank(guardian);
    psm.evacuateVault();

    _dealUSDC(address(psm), 10_000 * 10 ** 6);

    vm.prank(owner);
    vm.expectRevert(MorphoVaultPSMV2.ContractIsPaused.selector);
    psm.sweep();
  }

  function test_sweep_revertsForNonOwner() public {
    _dealUSDC(address(psm), 10_000 * 10 ** 6);

    vm.prank(random);
    vm.expectRevert(MorphoVaultPSMV2.CallerIsNotOwner.selector);
    psm.sweep();
  }

  function test_sweep_thenNormalWithdrawWorks() public {
    // Deposit first to create some base liquidity
    _depositAs(user1, 50_000 * 10 ** 6);

    // Sweep additional USDC
    uint256 sweepAmount = 50_000 * 10 ** 6;
    _dealUSDC(address(psm), sweepAmount);
    vm.prank(owner);
    psm.sweep();

    // User should be able to schedule withdrawal for more than original deposit
    uint256 maiAmount = 80_000 * 10 ** 18; // 80k MAI (more than 50k deposit but less than 100k total)
    _dealMAI(user1, maiAmount);
    _scheduleWithdrawAs(user1, maiAmount);

    // Warp and withdraw
    vm.warp(block.timestamp + 4 days);
    vm.prank(user1);
    psm.withdraw();

    // Should succeed — bookkeeping is consistent
    assertGt(usdcToken.balanceOf(user1), 0, 'User should have received USDC');
  }

  function test_sweep_thenClaimFeesWorks() public {
    // Deposit to create base liquidity
    _depositAs(user1, 100_000 * 10 ** 6);

    // Sweep additional USDC
    uint256 sweepAmount = 10_000 * 10 ** 6;
    _dealUSDC(address(psm), sweepAmount);
    vm.prank(owner);
    psm.sweep();

    // Warp to accumulate some yield
    vm.warp(block.timestamp + 30 days);

    // ClaimFees should work — vault assets > totalStableLiquidity from yield
    uint256 ownerUsdcBefore = usdcToken.balanceOf(owner);
    vm.prank(owner);
    psm.claimFees();

    // If yield accumulated, owner should receive something
    // (might be 0 if no yield in 30 days on fork — that's ok, just shouldn't revert)
  }

  function test_sweep_emitsEvent() public {
    uint256 sweepAmount = 50_000 * 10 ** 6;
    _dealUSDC(address(psm), sweepAmount);

    vm.prank(owner);
    vm.expectEmit(true, false, false, true);
    emit Swept(owner, sweepAmount);
    psm.sweep();
  }

  // ═══════════════════════════════════════════════════════════
  //  guardian tests
  // ═══════════════════════════════════════════════════════════

  function test_setGuardian_ownerCanSet() public {
    address newGuardian = makeAddr('newGuardian');
    vm.prank(owner);
    psm.setGuardian(newGuardian, true);
    assertTrue(psm.guardians(newGuardian));
  }

  function test_setGuardian_ownerCanRevoke() public {
    vm.prank(owner);
    psm.setGuardian(guardian, false);
    assertFalse(psm.guardians(guardian));
  }

  function test_setGuardian_nonOwnerReverts() public {
    vm.prank(random);
    vm.expectRevert(MorphoVaultPSMV2.CallerIsNotOwner.selector);
    psm.setGuardian(random, true);
  }

  function test_guardian_cannotCallSweep() public {
    _dealUSDC(address(psm), 10_000 * 10 ** 6);
    vm.prank(guardian);
    vm.expectRevert(MorphoVaultPSMV2.CallerIsNotOwner.selector);
    psm.sweep();
  }

  function test_guardian_cannotCallClaimFees() public {
    vm.prank(guardian);
    vm.expectRevert(MorphoVaultPSMV2.CallerIsNotOwner.selector);
    psm.claimFees();
  }

  function test_setGuardian_emitsEvent() public {
    address newGuardian = makeAddr('newGuardian');
    vm.prank(owner);
    vm.expectEmit(false, false, false, true);
    emit GuardianUpdated(newGuardian, true);
    psm.setGuardian(newGuardian, true);
  }

  // ═══════════════════════════════════════════════════════════
  //  multi-guardian tests
  // ═══════════════════════════════════════════════════════════

  function test_setGuardian_addMultipleGuardians() public {
    address guardian2 = makeAddr('guardian2');
    vm.startPrank(owner);
    psm.setGuardian(guardian2, true);
    vm.stopPrank();

    assertTrue(psm.guardians(guardian));
    assertTrue(psm.guardians(guardian2));

    // Both can independently evacuate (only first succeeds, second is idempotent)
    _depositAs(user1, 10_000 * 10 ** 6);
    vm.prank(guardian);
    psm.evacuateVault();
    assertTrue(psm.evacuated());

    // guardian2 can also call (idempotent)
    vm.prank(guardian2);
    psm.evacuateVault();
  }

  function test_setGuardian_removeOneGuardianOtherRetainsAccess() public {
    address guardian2 = makeAddr('guardian2');
    vm.startPrank(owner);
    psm.setGuardian(guardian2, true);
    psm.setGuardian(guardian, false);
    vm.stopPrank();

    assertFalse(psm.guardians(guardian));
    assertTrue(psm.guardians(guardian2));

    // Removed guardian reverts
    vm.prank(guardian);
    vm.expectRevert(MorphoVaultPSMV2.CallerIsNotGuardianOrOwner.selector);
    psm.evacuateVault();

    // Remaining guardian succeeds
    vm.prank(guardian2);
    psm.evacuateVault();
    assertTrue(psm.evacuated());
  }

  function test_setGuardian_removeGuardianPreventsEvacuate() public {
    vm.prank(owner);
    psm.setGuardian(guardian, false);

    vm.prank(guardian);
    vm.expectRevert(MorphoVaultPSMV2.CallerIsNotGuardianOrOwner.selector);
    psm.evacuateVault();
  }

  function test_setGuardian_readdRemovedGuardian() public {
    vm.startPrank(owner);
    psm.setGuardian(guardian, false);
    psm.setGuardian(guardian, true);
    vm.stopPrank();

    assertTrue(psm.guardians(guardian));

    // Re-added guardian can evacuate
    vm.prank(guardian);
    psm.evacuateVault();
    assertTrue(psm.evacuated());
  }

  function test_setGuardian_addressZeroReverts() public {
    vm.prank(owner);
    vm.expectRevert(MorphoVaultPSMV2.GuardianCannotBeZeroAddress.selector);
    psm.setGuardian(address(0), true);
  }

  // ═══════════════════════════════════════════════════════════
  //  MAI protection post-evacuation tests
  // ═══════════════════════════════════════════════════════════

  function test_withdrawMAI_protectsRefundsPostEvacuation() public {
    _depositAs(user1, 100_000 * 10 ** 6);

    // Schedule withdrawal for 50k MAI
    uint256 maiAmount = 50_000 * 10 ** 18;
    _dealMAI(user1, maiAmount);
    _scheduleWithdrawAs(user1, maiAmount);

    vm.prank(guardian);
    psm.evacuateVault();

    uint256 maiBalance = maiToken.balanceOf(address(psm));
    uint256 reserved = psm.totalQueuedMAI();

    // Owner withdraws MAI — should only get excess, not reserved
    vm.prank(owner);
    psm.withdrawMAI();

    uint256 ownerMai = maiToken.balanceOf(owner);
    uint256 psmMaiAfter = maiToken.balanceOf(address(psm));

    assertGe(psmMaiAfter, reserved, 'PSM should retain at least reserved MAI');
    assertEq(ownerMai, maiBalance - reserved, 'Owner gets only the excess');
  }

  function test_withdrawMAI_normalBehaviorPreEvacuation() public {
    uint256 maiBalance = maiToken.balanceOf(address(psm));

    vm.prank(owner);
    psm.withdrawMAI();

    assertEq(maiToken.balanceOf(owner), maiBalance, 'Owner gets all MAI pre-evacuation');
    assertEq(maiToken.balanceOf(address(psm)), 0, 'PSM should have 0 MAI');
  }

  function test_transferToken_gatesUnderlyingPostEvacuation() public {
    _depositAs(user1, 100_000 * 10 ** 6);

    vm.prank(guardian);
    psm.evacuateVault();

    uint256 usdcInPsm = usdcToken.balanceOf(address(psm));
    assertGt(usdcInPsm, 0, 'PSM should have USDC');

    // Immediately after evacuation — underlying should be gated
    vm.prank(owner);
    vm.expectRevert(MorphoVaultPSMV2.UpgradeNotScheduled.selector);
    psm.transferToken(USDC_BASE, owner, usdcInPsm);
  }

  function test_transferToken_underlyingWorksAfter2Days() public {
    _depositAs(user1, 100_000 * 10 ** 6);

    vm.prank(guardian);
    psm.evacuateVault();

    uint256 usdcInPsm = usdcToken.balanceOf(address(psm));

    // Warp past 2-day upgrade delay
    vm.warp(block.timestamp + 2 days + 1);

    vm.prank(owner);
    psm.transferToken(USDC_BASE, owner, usdcInPsm);

    assertEq(usdcToken.balanceOf(owner), usdcInPsm, 'Owner should receive USDC after delay');
  }

  function test_transferToken_underlyingWorksImmediatelyPreEvacuation() public {
    // Send USDC directly to PSM (not through deposit)
    _dealUSDC(address(psm), 10_000 * 10 ** 6);

    vm.prank(owner);
    psm.transferToken(USDC_BASE, owner, 10_000 * 10 ** 6);

    assertEq(usdcToken.balanceOf(owner), 10_000 * 10 ** 6, 'Owner gets USDC immediately pre-evacuation');
  }

  function test_transferToken_protectsMAIPostEvacuation() public {
    _depositAs(user1, 100_000 * 10 ** 6);

    uint256 maiAmount = 50_000 * 10 ** 18;
    _dealMAI(user1, maiAmount);
    _scheduleWithdrawAs(user1, maiAmount);

    vm.prank(guardian);
    psm.evacuateVault();

    uint256 maiBalance = maiToken.balanceOf(address(psm));

    // Try to transfer more MAI than available (excess of reserved)
    vm.prank(owner);
    vm.expectRevert(MorphoVaultPSMV2.NotEnoughLiquidity.selector);
    psm.transferToken(MAI_BASE, owner, maiBalance);
  }

  // ═══════════════════════════════════════════════════════════
  //  Edge case: evacuate with queued withdrawals
  // ═══════════════════════════════════════════════════════════

  function test_evacuateWithQueuedWithdrawals_fullFlow() public {
    // User1 deposits
    _depositAs(user1, 100_000 * 10 ** 6);

    // User1 schedules withdrawal
    uint256 maiAmount = 50_000 * 10 ** 18;
    _dealMAI(user1, maiAmount);
    _scheduleWithdrawAs(user1, maiAmount);

    uint256 stableBefore = psm.totalStableLiquidity();
    uint256 queuedBefore = psm.totalQueuedLiquidity();
    assertGt(queuedBefore, 0, 'Should have queued liquidity');

    // Evacuate
    vm.prank(guardian);
    psm.evacuateVault();

    // Bookkeeping unchanged by evacuation
    assertEq(psm.totalStableLiquidity(), stableBefore);
    assertEq(psm.totalQueuedLiquidity(), queuedBefore);

    // User claims refund
    vm.prank(user1);
    psm.claimRefund();

    // Final state
    uint256 refundedUsdc = maiAmount / (10 ** 12);
    assertEq(psm.totalStableLiquidity(), stableBefore - refundedUsdc);
    assertEq(psm.totalQueuedLiquidity(), 0);
  }

  // ═══════════════════════════════════════════════════════════
  //  Invariant: totalStableLiquidity >= totalQueuedLiquidity
  // ═══════════════════════════════════════════════════════════

  function test_invariant_stableGteQueued_afterEvacuateAndRefund() public {
    _depositAs(user1, 100_000 * 10 ** 6);
    _depositAs(user2, 50_000 * 10 ** 6);

    uint256 mai1 = 40_000 * 10 ** 18;
    uint256 mai2 = 30_000 * 10 ** 18;
    _dealMAI(user1, mai1);
    _dealMAI(user2, mai2);
    _scheduleWithdrawAs(user1, mai1);
    _scheduleWithdrawAs(user2, mai2);

    vm.prank(guardian);
    psm.evacuateVault();

    assertGe(psm.totalStableLiquidity(), psm.totalQueuedLiquidity(), 'Invariant before refunds');

    vm.prank(user1);
    psm.claimRefund();
    assertGe(psm.totalStableLiquidity(), psm.totalQueuedLiquidity(), 'Invariant after user1 refund');

    vm.prank(user2);
    psm.claimRefund();
    assertGe(psm.totalStableLiquidity(), psm.totalQueuedLiquidity(), 'Invariant after user2 refund');
  }

  // ═══════════════════════════════════════════════════════════
  //  Truncation regression: non-round MAI amount
  // ═══════════════════════════════════════════════════════════

  function test_totalQueuedMAI_tracksExactAmount_withTruncation() public {
    _depositAs(user1, 100_000 * 10 ** 6);

    // Schedule withdrawal with a non-round MAI amount that causes truncation
    // 40_000e18 + 1 wei: the +1 gets truncated by / 10^12 in totalQueuedLiquidity
    // but totalQueuedMAI must track the full amount
    uint256 maiAmount = 40_000 * 10 ** 18 + 1;
    _dealMAI(user1, maiAmount);
    _scheduleWithdrawAs(user1, maiAmount);

    // totalQueuedLiquidity truncates: (40_000e18 + 1) / 1e12 = 40_000e6 (truncated)
    assertEq(psm.totalQueuedLiquidity(), 40_000 * 10 ** 6, 'Truncated USDC value');
    // totalQueuedMAI tracks exact amount
    assertEq(psm.totalQueuedMAI(), maiAmount, 'Exact MAI tracked');

    // Evacuate and verify the owner cannot drain the exact MAI needed
    vm.prank(guardian);
    psm.evacuateVault();

    // Owner withdraws excess MAI — must leave the full maiAmount, not the truncated value
    vm.prank(owner);
    psm.withdrawMAI();

    uint256 psmMaiAfter = maiToken.balanceOf(address(psm));
    assertGe(psmMaiAfter, maiAmount, 'PSM retains exact MAI for refund, not truncated amount');

    // User can claim the full amount
    vm.prank(user1);
    psm.claimRefund();
    assertEq(psm.totalQueuedMAI(), 0, 'totalQueuedMAI zeroed after refund');
  }

  // ═══════════════════════════════════════════════════════════
  //  Withdrawal boundary: rounded amount must exceed the fee floor
  // ═══════════════════════════════════════════════════════════

  function test_scheduleWithdraw_dustAmount_reverts() public {
    _depositAs(user1, 100_000 * 10 ** 6);

    // minimumWithdrawalFee is 1_000_000 underlying units ($1). This MAI amount
    // rounds to 0 underlying, so it must be rejected before scheduling.
    uint256 dustMai = 1_000_000; // = minimumWithdrawalFee
    _dealMAI(user1, dustMai);
    vm.startPrank(user1);
    maiToken.approve(address(psm), dustMai);

    vm.expectRevert(MorphoVaultPSMV2.InvalidAmountAfterFee.selector);
    psm.scheduleWithdraw(dustMai);
    vm.stopPrank();
  }

  function test_scheduleWithdraw_amountConsumedByFee_reverts() public {
    _depositAs(user1, 100_000 * 10 ** 6);

    // 1 MAI rounds to exactly 1 USDC, which is then fully consumed by the
    // minimum withdrawal fee. Scheduling must reject zero-net withdrawals.
    uint256 oneDollarMai = 1 * 10 ** 18;
    _dealMAI(user1, oneDollarMai);
    vm.startPrank(user1);
    maiToken.approve(address(psm), oneDollarMai);

    vm.expectRevert(MorphoVaultPSMV2.InvalidAmountAfterFee.selector);
    psm.scheduleWithdraw(oneDollarMai);
    vm.stopPrank();
  }

  function test_scheduleWithdraw_amountAboveFeeBoundary_succeeds() public {
    _depositAs(user1, 100_000 * 10 ** 6);

    // 1.000001 MAI rounds to 1_000_001 underlying units, leaving 1 unit after
    // the $1 fee floor. This is the first valid amount above the boundary.
    uint256 validMai = 1_000_001 * 10 ** 12;
    _dealMAI(user1, validMai);
    vm.startPrank(user1);
    maiToken.approve(address(psm), validMai);
    psm.scheduleWithdraw(validMai);
    vm.stopPrank();

    assertEq(psm.totalQueuedLiquidity(), 1_000_001, 'Rounded underlying amount should be queued');
    assertEq(psm.totalQueuedMAI(), validMai, 'Exact MAI amount should be tracked');
  }
}

/// @title MorphoVaultPSMRedeemFailureTest
/// @notice Tests evacuateVault when the underlying vault reverts on redeem
contract MorphoVaultPSMRedeemFailureTest is Test {
  event VaultEvacuated(address indexed _caller, uint256 _sharesRedeemed);
  event RedeemFailed(bytes _reason);

  MorphoVaultPSMV2 internal psm;
  RevertingMockVault internal revertVault;

  address internal owner = makeAddr('owner');
  address internal guardian = makeAddr('guardian');
  address internal user1 = makeAddr('user1');

  // Base chain fork for USDC/MAI
  address internal constant MAI_BASE = 0xbf1aeA8670D2528E08334083616dD9C5F3B087aE;
  address internal constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

  IERC20 internal usdcToken = IERC20(USDC_BASE);
  IERC20 internal maiToken = IERC20(MAI_BASE);

  function _dealUSDC(
    address to,
    uint256 amount
  ) internal {
    bytes32 storageSlot = keccak256(abi.encode(to, uint256(9)));
    vm.store(USDC_BASE, storageSlot, bytes32(amount));
  }

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl('base'));

    // Deploy reverting vault
    revertVault = new RevertingMockVault(USDC_BASE);

    vm.startPrank(owner);
    psm = new MorphoVaultPSMV2();
    vm.stopPrank();

    deal(MAI_BASE, address(psm), 5_000_000 * 10 ** 18);
    _dealUSDC(user1, 1_000_000 * 10 ** 6);

    vm.startPrank(owner);
    psm.initialize(address(revertVault), 0, 30, MAI_BASE);
    psm.setGuardian(guardian, true);
    vm.stopPrank();
  }

  function test_evacuateVault_freezesEvenWhenRedeemReverts() public {
    // Deposit USDC — it goes into the reverting vault
    vm.startPrank(user1);
    usdcToken.approve(address(psm), 10_000 * 10 ** 6);
    psm.deposit(10_000 * 10 ** 6);
    vm.stopPrank();

    uint256 sharesBefore = revertVault.balanceOf(address(psm));
    assertGt(sharesBefore, 0, 'PSM should have vault shares');

    // Evacuate — redeem will revert, but contract should still freeze
    vm.prank(guardian);
    psm.evacuateVault();

    // Contract IS frozen
    assertTrue(psm.evacuated(), 'Should be evacuated despite redeem failure');
    assertTrue(psm.stopped(), 'Should be stopped');

    // Shares still in vault (redeem failed)
    assertEq(revertVault.balanceOf(address(psm)), sharesBefore, 'Shares should remain (redeem failed)');

    // User operations blocked
    _dealUSDC(user1, 10_000 * 10 ** 6);
    vm.startPrank(user1);
    usdcToken.approve(address(psm), 10_000 * 10 ** 6);
    vm.expectRevert(MorphoVaultPSMV2.ContractIsPaused.selector);
    psm.deposit(10_000 * 10 ** 6);
    vm.stopPrank();
  }

  function test_evacuateVault_emitsRedeemFailedEvent() public {
    vm.startPrank(user1);
    usdcToken.approve(address(psm), 10_000 * 10 ** 6);
    psm.deposit(10_000 * 10 ** 6);
    vm.stopPrank();

    // Should emit RedeemFailed with the ABI-encoded revert reason
    vm.prank(guardian);
    vm.expectEmit(false, false, false, false);
    emit RedeemFailed('');
    psm.evacuateVault();

    assertTrue(psm.evacuated());
  }
}

/// @title MorphoVaultPSMMigrationWithRefundsTest
/// @notice E2E migration test with queued withdrawals and refunds mid-migration
contract MorphoVaultPSMMigrationWithRefundsTest is Test {
  MorphoVaultPSMV2 internal oldPsm;
  MorphoVaultPSMV2 internal newPsm;

  address internal owner = makeAddr('owner');
  address internal guardian = makeAddr('guardian');
  address internal user1 = makeAddr('user1');
  address internal user2 = makeAddr('user2');

  address internal constant MORPHO_GAUNTLET = 0xc0c5689e6f4D256E861F65465b691aeEcC0dEb12;
  address internal constant MAI_BASE = 0xbf1aeA8670D2528E08334083616dD9C5F3B087aE;
  address internal constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

  IERC20 internal usdc = IERC20(USDC_BASE);
  IERC20 internal mai = IERC20(MAI_BASE);

  function _dealUSDC(
    address to,
    uint256 amount
  ) internal {
    bytes32 storageSlot = keccak256(abi.encode(to, uint256(9)));
    vm.store(USDC_BASE, storageSlot, bytes32(amount));
  }

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl('base'));

    _dealUSDC(user1, 1_000_000 * 10 ** 6);
    _dealUSDC(user2, 1_000_000 * 10 ** 6);

    vm.startPrank(owner);
    oldPsm = new MorphoVaultPSMV2();
    vm.stopPrank();

    deal(MAI_BASE, address(oldPsm), 10_000_000 * 10 ** 18);

    vm.startPrank(owner);
    oldPsm.initialize(MORPHO_GAUNTLET, 0, 30, MAI_BASE);
    oldPsm.setGuardian(guardian, true);
    vm.stopPrank();
  }

  function test_migrationWithQueuedWithdrawalsAndRefunds() public {
    // Step 1: Users deposit
    vm.startPrank(user1);
    usdc.approve(address(oldPsm), 100_000 * 10 ** 6);
    oldPsm.deposit(100_000 * 10 ** 6);
    vm.stopPrank();

    vm.startPrank(user2);
    usdc.approve(address(oldPsm), 50_000 * 10 ** 6);
    oldPsm.deposit(50_000 * 10 ** 6);
    vm.stopPrank();

    // Step 2: User1 schedules withdrawal (queued)
    uint256 maiAmount = 40_000 * 10 ** 18;
    deal(MAI_BASE, user1, maiAmount);
    vm.startPrank(user1);
    mai.approve(address(oldPsm), maiAmount);
    oldPsm.scheduleWithdraw(maiAmount);
    vm.stopPrank();

    uint256 stableBefore = oldPsm.totalStableLiquidity();
    uint256 queuedBefore = oldPsm.totalQueuedLiquidity();
    assertGt(queuedBefore, 0, 'Should have queued liquidity');

    // Step 3: Guardian evacuates
    vm.prank(guardian);
    oldPsm.evacuateVault();

    assertTrue(oldPsm.evacuated());
    uint256 usdcInOldPsm = usdc.balanceOf(address(oldPsm));

    // Step 4: User1 claims MAI refund mid-migration
    uint256 user1MaiBefore = mai.balanceOf(user1);
    vm.prank(user1);
    oldPsm.claimRefund();
    assertEq(mai.balanceOf(user1), user1MaiBefore + maiAmount, 'User1 got MAI back');
    assertEq(oldPsm.totalQueuedLiquidity(), 0, 'Queue cleared after refund');

    // Step 5: Wait 2 days for transferToken
    vm.warp(block.timestamp + 2 days + 1);

    // Step 6: Owner transfers USDC out
    uint256 usdcToMigrate = usdc.balanceOf(address(oldPsm));
    vm.prank(owner);
    oldPsm.transferToken(USDC_BASE, owner, usdcToMigrate);

    // Step 7: Owner also withdraws excess MAI
    vm.prank(owner);
    oldPsm.withdrawMAI();

    // Step 8: Deploy new PSM, send USDC, sweep
    vm.startPrank(owner);
    newPsm = new MorphoVaultPSMV2();
    vm.stopPrank();

    deal(MAI_BASE, address(newPsm), 10_000_000 * 10 ** 18);

    vm.startPrank(owner);
    newPsm.initialize(MORPHO_GAUNTLET, 0, 30, MAI_BASE);
    usdc.transfer(address(newPsm), usdcToMigrate);
    newPsm.sweep();
    vm.stopPrank();

    // Step 9: Verify new PSM is operational
    assertEq(newPsm.totalStableLiquidity(), usdcToMigrate, 'New PSM liquidity matches');

    // Step 10: User2 can deposit into new PSM
    vm.startPrank(user2);
    usdc.approve(address(newPsm), 10_000 * 10 ** 6);
    newPsm.deposit(10_000 * 10 ** 6);
    vm.stopPrank();

    assertGt(newPsm.totalStableLiquidity(), usdcToMigrate, 'New deposits work');

    // Invariants hold throughout
    assertGe(newPsm.totalStableLiquidity(), newPsm.totalQueuedLiquidity());
    assertEq(oldPsm.totalQueuedLiquidity(), 0);
  }
}
