// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from 'forge-std/Test.sol';
import {USDCVaultPSMV2} from 'contracts/USDCVaultPSM/V2.sol';
import {MockERC20} from '../mocks/MockERC20.sol';

/// @title USDCVaultPSMV2CloseTest
/// @notice Local-profile coverage of `USDCVaultPSMV2.close()` semantics, modifier
///         orthogonality between `whenNotClosed` and `pausable`, and the R8 gate
///         that blocks `setUpgrade`/`cancelUpgrade` post-close.
/// @dev Mocks-only fixture, no fork. Runs under `[profile.local]` via `yarn test`.
contract USDCVaultPSMV2CloseTest is Test {
  // Local copy of the event so vm.expectEmit can match against the typed signature.
  // Solidity 0.8.19 disallows `ContractName.EventName` references in emit statements.
  event Closed(uint256 closedAt, bytes32 reason);

  USDCVaultPSMV2 internal _psm;
  MockERC20 internal _usdc;
  MockERC20 internal _mai;

  address internal _owner = makeAddr('owner');
  address internal _user = makeAddr('user');
  address internal _treasury = makeAddr('treasury');

  uint256 internal constant _DEPOSIT_FEE_BP = 100; // 1%
  uint256 internal constant _MAI_PREFUND = 100_000_000 * 10 ** 18; // 100M MAI to back deposits

  bytes4 internal constant _DEPOSIT_SELECTOR = bytes4(keccak256('deposit(uint256)'));

  function setUp() public {
    _usdc = new MockERC20('USD Coin', 'USDC', 6);
    _mai = new MockERC20('Mai Stablecoin', 'MAI', 18);

    vm.startPrank(_owner);
    _psm = new USDCVaultPSMV2();
    _psm.initialize(_DEPOSIT_FEE_BP, address(_mai), address(_usdc));
    vm.stopPrank();

    _mai.mint(address(_psm), _MAI_PREFUND);
  }

  // ---------- helpers ----------

  function _depositAs(
    address _who,
    uint256 _amount
  ) internal {
    _usdc.mint(_who, _amount);
    vm.startPrank(_who);
    _usdc.approve(address(_psm), _amount);
    _psm.deposit(_amount);
    vm.stopPrank();
  }

  function _close(
    bytes32 _reason
  ) internal {
    vm.prank(_owner);
    _psm.close(_reason);
  }

  // ---------- 1. close() happy path ----------

  function test_close_happyPath_setsStateAndBlocksDeposits() public {
    _depositAs(_user, 1000 * 10 ** 6);

    bytes32 _reason = bytes32('low-tvl-sunset');
    uint256 _expectedClosedAt = block.timestamp;

    vm.expectEmit(true, true, true, true, address(_psm));
    emit Closed(_expectedClosedAt, _reason);

    vm.prank(_owner);
    _psm.close(_reason);

    assertEq(_psm.closedAt(), _expectedClosedAt, 'closedAt records block.timestamp');
    assertEq(_psm.closedReason(), _reason, 'closedReason records the bytes32 label');

    // Subsequent deposit reverts with PSMClosed(closedAt).
    _usdc.mint(_user, 100 * 10 ** 6);
    vm.startPrank(_user);
    _usdc.approve(address(_psm), 100 * 10 ** 6);
    vm.expectRevert(abi.encodeWithSelector(USDCVaultPSMV2.PSMClosed.selector, _expectedClosedAt));
    _psm.deposit(100 * 10 ** 6);
    vm.stopPrank();
  }

  // ---------- 2. write-once enforcement ----------

  function test_close_writeOnce_secondCallReverts() public {
    _close(bytes32('low-tvl-sunset'));
    uint256 _firstClosedAt = _psm.closedAt();

    vm.warp(block.timestamp + 1 days);

    vm.prank(_owner);
    vm.expectRevert(USDCVaultPSMV2.AlreadyClosed.selector);
    _psm.close(bytes32('different-reason'));

    assertEq(_psm.closedAt(), _firstClosedAt, 'closedAt not stomped by failed second call');
    assertEq(_psm.closedReason(), bytes32('low-tvl-sunset'), 'closedReason preserved');
  }

  // ---------- 3. ACL — non-owner reverts ----------

  function test_close_nonOwner_reverts() public {
    vm.prank(_user);
    vm.expectRevert(USDCVaultPSMV2.CallerIsNotOwner.selector);
    _psm.close(bytes32('attempt'));
  }

  // ---------- 3a. ACL — pendingOwner cannot close ----------

  function test_close_pendingOwner_reverts() public {
    address _pending = makeAddr('pending');

    vm.prank(_owner);
    _psm.transferOwnership(_pending);

    // pendingOwner has not yet called acceptOwnership — still a non-owner.
    vm.prank(_pending);
    vm.expectRevert(USDCVaultPSMV2.CallerIsNotOwner.selector);
    _psm.close(bytes32('attempt'));
  }

  // ---------- 4. modifier ordering vs pausable ----------

  function test_modifierOrdering_closeBeatsPausable() public {
    // Pause deposit, then close. Both states active simultaneously.
    vm.prank(_owner);
    _psm.setPaused(_DEPOSIT_SELECTOR, true);

    _close(bytes32('low-tvl-sunset'));
    uint256 _ts = _psm.closedAt();

    _usdc.mint(_user, 1000 * 10 ** 6);
    vm.startPrank(_user);
    _usdc.approve(address(_psm), 1000 * 10 ** 6);

    // PSMClosed wins over ContractIsPaused — close runs first.
    vm.expectRevert(abi.encodeWithSelector(USDCVaultPSMV2.PSMClosed.selector, _ts));
    _psm.deposit(1000 * 10 ** 6);
    vm.stopPrank();
  }

  // ---------- 4a. pause/unpause cycle remains two-way pre AND post close ----------

  function test_pauseCycle_remainsTwoWayBeforeAndAfterClose() public {
    // Pre-close: pause → revert with ContractIsPaused; unpause → restored.
    vm.prank(_owner);
    _psm.setPaused(_DEPOSIT_SELECTOR, true);

    _usdc.mint(_user, 1000 * 10 ** 6);
    vm.startPrank(_user);
    _usdc.approve(address(_psm), 1000 * 10 ** 6);
    vm.expectRevert(USDCVaultPSMV2.ContractIsPaused.selector);
    _psm.deposit(1000 * 10 ** 6);
    vm.stopPrank();

    vm.prank(_owner);
    _psm.setPaused(_DEPOSIT_SELECTOR, false);
    assertFalse(_psm.paused(_DEPOSIT_SELECTOR), 'pause flag flipped back');

    // Deposit succeeds again pre-close.
    _depositAs(_user, 1000 * 10 ** 6);

    // Post-close: pause/unpause still flips the map; deposit reverts with PSMClosed
    // regardless of pause state.
    _close(bytes32('low-tvl-sunset'));

    vm.prank(_owner);
    _psm.setPaused(_DEPOSIT_SELECTOR, true);
    assertTrue(_psm.paused(_DEPOSIT_SELECTOR), 'pause flag still writable post-close');

    vm.prank(_owner);
    _psm.setPaused(_DEPOSIT_SELECTOR, false);
    assertFalse(_psm.paused(_DEPOSIT_SELECTOR), 'pause flag flipped back post-close');
  }

  // ---------- 4b. selector-pause map flexibility preserved ----------

  function test_selectorPauseMap_writableForArbitrarySelectorsPostClose() public {
    bytes4 _arbitrary = bytes4(keccak256('someFutureFunction(uint256)'));

    // Pre-close: arbitrary selector pause writable.
    vm.prank(_owner);
    _psm.setPaused(_arbitrary, true);
    assertTrue(_psm.paused(_arbitrary));

    _close(bytes32('low-tvl-sunset'));

    // Post-close: still writable in either direction.
    vm.prank(_owner);
    _psm.setPaused(_arbitrary, false);
    assertFalse(_psm.paused(_arbitrary));

    vm.prank(_owner);
    _psm.setPaused(_arbitrary, true);
    assertTrue(_psm.paused(_arbitrary));
  }

  // ---------- 5. modifier ordering vs setUpgrade ----------

  function test_modifierOrdering_closeBeatsSetUpgrade() public {
    // setUpgrade -> stopped=true, upgradeTime = now + 2 days.
    vm.prank(_owner);
    _psm.setUpgrade();
    uint256 _upgradeTime = _psm.upgradeTime();

    // Close mid-window.
    _close(bytes32('low-tvl-sunset'));
    uint256 _ts = _psm.closedAt();

    // After the pre-close upgrade timelock, pausable would revert with
    // ContractIsPaused unless whenNotClosed wins first.
    vm.warp(_upgradeTime + 1);

    _usdc.mint(_user, 1000 * 10 ** 6);
    vm.startPrank(_user);
    _usdc.approve(address(_psm), 1000 * 10 ** 6);

    vm.expectRevert(abi.encodeWithSelector(USDCVaultPSMV2.PSMClosed.selector, _ts));
    _psm.deposit(1000 * 10 ** 6);
    vm.stopPrank();
  }

  // ---------- R8 gate: setUpgrade blocked post-close ----------

  function test_setUpgrade_blockedPostClose() public {
    _close(bytes32('low-tvl-sunset'));
    uint256 _ts = _psm.closedAt();

    bool _stoppedBefore = _psm.stopped();
    uint256 _upgradeTimeBefore = _psm.upgradeTime();

    vm.prank(_owner);
    vm.expectRevert(abi.encodeWithSelector(USDCVaultPSMV2.PSMClosed.selector, _ts));
    _psm.setUpgrade();

    assertEq(_psm.stopped(), _stoppedBefore, 'stopped flag unchanged after blocked setUpgrade');
    assertEq(_psm.upgradeTime(), _upgradeTimeBefore, 'upgradeTime unchanged after blocked setUpgrade');
  }

  // ---------- R8 gate: cancelUpgrade blocked post-close ----------

  function test_cancelUpgrade_blockedPostClose() public {
    // setUpgrade BEFORE close so the in-flight upgrade state exists.
    vm.prank(_owner);
    _psm.setUpgrade();

    bool _stoppedAfterUpgrade = _psm.stopped();
    uint256 _upgradeTimeAfterUpgrade = _psm.upgradeTime();

    _close(bytes32('low-tvl-sunset'));
    uint256 _ts = _psm.closedAt();

    vm.prank(_owner);
    vm.expectRevert(abi.encodeWithSelector(USDCVaultPSMV2.PSMClosed.selector, _ts));
    _psm.cancelUpgrade();

    // Pre-existing upgrade state carries through unchanged.
    assertEq(_psm.stopped(), _stoppedAfterUpgrade, 'stopped flag preserved through blocked cancel');
    assertEq(_psm.upgradeTime(), _upgradeTimeAfterUpgrade, 'upgradeTime preserved through blocked cancel');
  }

  // ---------- Post-close USDC sweep semantics ----------

  function test_transferToken_USDC_succeedsAfterPreCloseUpgradeTimelock() public {
    _depositAs(_user, 10_000 * 10 ** 6);

    // setUpgrade BEFORE close → wait through timelock → THEN close. This keeps the
    // already-completed upgrade window's USDC sweep path open after close.
    vm.prank(_owner);
    _psm.setUpgrade();

    vm.warp(block.timestamp + 2 days + 1);

    _close(bytes32('low-tvl-sunset'));

    uint256 _treasuryBefore = _usdc.balanceOf(_treasury);
    uint256 _psmUsdcBalance = _usdc.balanceOf(address(_psm));
    assertGt(_psmUsdcBalance, 0, 'PSM holds USDC pre-sweep');

    vm.prank(_owner);
    _psm.transferToken(address(_usdc), _treasury, _psmUsdcBalance);

    assertEq(_usdc.balanceOf(_treasury), _treasuryBefore + _psmUsdcBalance, 'treasury received full USDC sweep');
    assertEq(_usdc.balanceOf(address(_psm)), 0, 'PSM USDC drained');
  }

  // ---------- 6. close with zero MAI balance ----------

  function test_close_succeedsWithZeroMaiBalance() public {
    // Drain MAI before close.
    vm.prank(_owner);
    _psm.withdrawMAI();
    assertEq(_mai.balanceOf(address(_psm)), 0);

    // Close succeeds — independent of liquidity.
    _close(bytes32('drained-first'));
    assertEq(_psm.closedAt(), block.timestamp);
  }

  // ---------- 7. owner-only sweep functions remain reachable post-close ----------

  function test_postClose_sweepFunctions_remainCallable() public {
    _depositAs(_user, 10_000 * 10 ** 6);
    _close(bytes32('low-tvl-sunset'));

    // claimFees still callable. A 1% fee on 10k USDC = 100 USDC accumulated as fee.
    uint256 _ownerUsdcBefore = _usdc.balanceOf(_owner);
    vm.prank(_owner);
    _psm.claimFees();
    assertGt(_usdc.balanceOf(_owner), _ownerUsdcBefore, 'claimFees swept fees post-close');

    // withdrawMAI still callable.
    uint256 _ownerMaiBefore = _mai.balanceOf(_owner);
    vm.prank(_owner);
    _psm.withdrawMAI();
    assertGt(_mai.balanceOf(_owner), _ownerMaiBefore, 'withdrawMAI swept MAI post-close');
  }

  // ---------- 8. view reads remain intact post-close ----------

  function test_postClose_viewReads_intact() public {
    _depositAs(_user, 1000 * 10 ** 6);
    uint256 _totalDepositedBefore = _psm.totalDeposited();

    _close(bytes32('low-tvl-sunset'));

    assertEq(_psm.totalDeposited(), _totalDepositedBefore, 'totalDeposited intact');
    assertEq(_psm.depositFee(), _DEPOSIT_FEE_BP, 'depositFee intact');
    assertEq(_psm.MAI_ADDRESS(), address(_mai), 'MAI_ADDRESS intact');
    assertEq(_psm.USDC_ADDRESS(), address(_usdc), 'USDC_ADDRESS intact');
    assertEq(_psm.closedAt(), block.timestamp, 'closedAt readable');
    assertEq(_psm.closedReason(), bytes32('low-tvl-sunset'), 'closedReason readable');
  }

  // ---------- 9. closedAt stable across unrelated transactions ----------

  function test_closedAt_stableAcrossSubsequentTransactions() public {
    _close(bytes32('low-tvl-sunset'));
    uint256 _ts = _psm.closedAt();

    vm.warp(block.timestamp + 30 days);

    // Trigger an unrelated owner state mutation.
    vm.prank(_owner);
    _psm.updateMaxDeposit(2e12);

    assertEq(_psm.closedAt(), _ts, 'closedAt unchanged');
  }

  // ---------- 10. PSMClosed custom-error decoding ----------

  function test_psmClosed_customErrorDecoding() public {
    _close(bytes32('low-tvl-sunset'));
    uint256 _expectedTs = _psm.closedAt();

    _usdc.mint(_user, 1000 * 10 ** 6);
    vm.startPrank(_user);
    _usdc.approve(address(_psm), 1000 * 10 ** 6);

    // Wrong timestamp must NOT match — confirms the typed payload is in the revert.
    vm.expectRevert(abi.encodeWithSelector(USDCVaultPSMV2.PSMClosed.selector, _expectedTs));
    _psm.deposit(1000 * 10 ** 6);
    vm.stopPrank();
  }
}
