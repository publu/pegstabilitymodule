// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {AaveUSDPSMV1} from 'contracts/AaveUSDPSM/V1.sol';
import {AaveLocalPoly} from './AaveLocalPoly.sol';

contract AaveUSDPSMCoreTest is AaveLocalPoly {
  function setUp() public override {
    super.setUp();
    vm.startPrank(_owner);
  }

  // --- initialize ---

  function test_initialize_wiresPoolAndUnderlyingFromAToken() public {
    assertEq(_psm.gem(), address(_aTokenMock), 'gem should be the aToken');
    assertEq(_psm.pool(), address(_poolMock), 'pool should be derived from aToken.POOL()');
    assertEq(_psm.underlying(), address(_usdcMock), 'underlying should be derived from aToken.UNDERLYING_ASSET_ADDRESS()');
    assertEq(_psm.MAI_ADDRESS(), address(_maiMock), 'MAI address should be set from init');
    assertEq(_psm.decimalDifference(), 12, 'decimalDifference should be MAI(18) - USDC(6) = 12');
    assertEq(_psm.owner(), _owner, 'owner should be deployer');
    assertTrue(_psm.initialized(), 'initialized flag');
  }

  function test_initialize_revertsOnSecondCall() public {
    vm.expectRevert(AaveUSDPSMV1.AlreadyInitialized.selector);
    _psm.initialize(address(_aTokenMock), 100, 100, address(_maiMock));
  }

  function test_initialize_revertsOnZeroMAI() public {
    AaveUSDPSMV1 fresh = new AaveUSDPSMV1();
    vm.expectRevert(AaveUSDPSMV1.MAIAddressCannotBeZero.selector);
    fresh.initialize(address(_aTokenMock), 100, 100, address(0));
  }

  // --- deposit happy path ---

  function test_deposit_suppliesToPoolAndPaysMAI() public {
    uint256 amount = 1000 * 10 ** 6;
    vm.stopPrank();
    vm.startPrank(_user);
    _usdcMock.approve(address(_psm), amount);

    uint256 userUsdcBefore = _usdcMock.balanceOf(_user);
    uint256 userMaiBefore = _maiMock.balanceOf(_user);

    _psm.deposit(amount);

    uint256 fee = _psm.calculateFee(amount, true);
    uint256 expectedStable = amount - fee;
    uint256 expectedMAI = expectedStable * 10 ** 12;

    assertEq(_usdcMock.balanceOf(_user), userUsdcBefore - amount, 'USDC pulled from user');
    assertEq(_maiMock.balanceOf(_user), userMaiBefore + expectedMAI, 'User received MAI = (amount-fee) * 1e12');
    assertEq(_aTokenMock.balanceOf(address(_psm)), amount, 'PSM holds full amount in aToken (fee included)');
    assertEq(_usdcMock.balanceOf(address(_psm)), 0, 'No idle USDC on PSM after supply');
    assertEq(_psm.totalStableLiquidity(), expectedStable, 'totalStableLiquidity tracks net of fee');
  }

  function test_deposit_revertsBelowMinimumDepositFee() public {
    uint256 tiny = _psm.minimumDepositFee(); // boundary
    _usdcMock.approve(address(_psm), tiny);
    vm.expectRevert(AaveUSDPSMV1.InvalidAmount.selector);
    _psm.deposit(tiny);
  }

  function test_deposit_revertsAboveMaxDeposit() public {
    uint256 huge = _psm.maxDeposit() + 1;
    _usdcMock.mint(_owner, huge);
    _usdcMock.approve(address(_psm), huge);
    vm.expectRevert(AaveUSDPSMV1.InvalidAmount.selector);
    _psm.deposit(huge);
  }

  function test_deposit_revertsWhenSelectorPaused() public {
    _psm.setPaused(AaveUSDPSMV1.deposit.selector, true);
    uint256 amount = 1000 * 10 ** 6;
    _usdcMock.approve(address(_psm), amount);
    vm.expectRevert(AaveUSDPSMV1.ContractIsPaused.selector);
    _psm.deposit(amount);
  }

  // --- scheduleWithdraw + withdraw ---

  function test_scheduleThenWithdraw_payoutsNetUSDCDirectToUser() public {
    // Owner seeds the PSM with USDC liquidity.
    uint256 deposit = 10_000 * 10 ** 6;
    _usdcMock.approve(address(_psm), deposit);
    _psm.deposit(deposit);

    vm.stopPrank();
    vm.startPrank(_user);

    uint256 withdrawMAI = 1000 * 10 ** 18; // 1000 MAI -> 1000 USDC gross
    _maiMock.mint(_user, withdrawMAI);
    _maiMock.approve(address(_psm), withdrawMAI);

    uint256 psmMaiPreSchedule = _maiMock.balanceOf(address(_psm));
    _psm.scheduleWithdraw(withdrawMAI);

    assertEq(_psm.totalQueuedLiquidity(), 1000 * 10 ** 6, 'totalQueuedLiquidity updated');
    assertEq(_psm.totalQueuedMAI(), withdrawMAI, 'totalQueuedMAI updated');
    assertEq(_maiMock.balanceOf(address(_psm)), psmMaiPreSchedule + withdrawMAI, 'MAI pulled from user into PSM');

    vm.warp(block.timestamp + 4 days);

    uint256 userUsdcBefore = _usdcMock.balanceOf(_user);
    uint256 psmATokenBefore = _aTokenMock.balanceOf(address(_psm));

    _psm.withdraw();

    uint256 fee = _psm.calculateFee(1000 * 10 ** 6, false);
    uint256 expectedPayout = 1000 * 10 ** 6 - fee;

    assertEq(_usdcMock.balanceOf(_user), userUsdcBefore + expectedPayout, 'User receives net USDC');
    assertEq(
      _aTokenMock.balanceOf(address(_psm)),
      psmATokenBefore - expectedPayout,
      'aToken decreases by payout only; fee stays as yield'
    );
    assertEq(_psm.totalStableLiquidity(), deposit - _psm.calculateFee(deposit, true) - 1000 * 10 ** 6, 'totalStableLiquidity shrinks by gross');
    assertEq(_psm.totalQueuedLiquidity(), 0, 'queue cleared');
    assertEq(_psm.totalQueuedMAI(), 0, 'queue MAI cleared');
  }

  function test_scheduleWithdraw_revertsWhenAlreadyScheduled() public {
    _usdcMock.approve(address(_psm), 10_000 * 10 ** 6);
    _psm.deposit(10_000 * 10 ** 6);

    vm.stopPrank();
    vm.startPrank(_user);
    _maiMock.mint(_user, 2000 * 10 ** 18);
    _maiMock.approve(address(_psm), 2000 * 10 ** 18);
    _psm.scheduleWithdraw(1000 * 10 ** 18);

    vm.expectRevert(AaveUSDPSMV1.WithdrawalAlreadyScheduled.selector);
    _psm.scheduleWithdraw(1000 * 10 ** 18);
  }

  function test_withdraw_revertsBeforeEpoch() public {
    _usdcMock.approve(address(_psm), 10_000 * 10 ** 6);
    _psm.deposit(10_000 * 10 ** 6);

    vm.stopPrank();
    vm.startPrank(_user);
    _maiMock.mint(_user, 1000 * 10 ** 18);
    _maiMock.approve(address(_psm), 1000 * 10 ** 18);
    _psm.scheduleWithdraw(1000 * 10 ** 18);

    // 2 days, still < 3-day epoch
    vm.warp(block.timestamp + 2 days);

    vm.expectRevert(AaveUSDPSMV1.WithdrawalNotAvailable.selector);
    _psm.withdraw();
  }

  // --- claimFees ---

  function test_claimFees_paysOnlyYieldAboveLiabilities() public {
    uint256 deposit = 10_000 * 10 ** 6;
    _usdcMock.approve(address(_psm), deposit);
    _psm.deposit(deposit);

    uint256 depositFee = _psm.calculateFee(deposit, true);
    uint256 preClaim = _usdcMock.balanceOf(_owner);
    uint256 aTokenPreClaim = _aTokenMock.balanceOf(address(_psm));

    // Simulate rebasing yield: aToken grows by 500 USDC.
    _poolMock.simulateYield(address(_psm), 500 * 10 ** 6);

    _psm.claimFees();

    uint256 expectedYield = 500 * 10 ** 6 + depositFee; // fee + rebased yield
    assertEq(_usdcMock.balanceOf(_owner), preClaim + expectedYield, 'owner receives deposit fee + rebased yield');
    assertEq(_aTokenMock.balanceOf(address(_psm)), aTokenPreClaim + 500 * 10 ** 6 - expectedYield, 'aToken balance decreases by yield withdrawn');
    assertEq(_aTokenMock.balanceOf(address(_psm)), _psm.totalStableLiquidity(), 'post-claim: aToken == liabilities');
  }

  function test_claimFees_noOpWhenNoYield() public {
    _usdcMock.approve(address(_psm), 10_000 * 10 ** 6);
    _psm.deposit(10_000 * 10 ** 6);

    // Fresh deposit leaves fee as yield over liabilities; claim it.
    _psm.claimFees();

    uint256 preSecondClaim = _usdcMock.balanceOf(_owner);
    _psm.claimFees(); // second claim — nothing to pay

    assertEq(_usdcMock.balanceOf(_owner), preSecondClaim, 'second claimFees is a no-op');
  }

  // --- admin surface ---

  function test_onlyOwner_guardsConfig() public {
    vm.stopPrank();
    vm.startPrank(_user);

    vm.expectRevert(AaveUSDPSMV1.CallerIsNotOwner.selector);
    _psm.updateFeesBP(50, 50);

    vm.expectRevert(AaveUSDPSMV1.CallerIsNotOwner.selector);
    _psm.setMinimumReserves(1000);

    vm.expectRevert(AaveUSDPSMV1.CallerIsNotOwner.selector);
    _psm.setGuardian(_user, true);
  }

  function test_setUpgrade_enablesTransferTokenAfterDelay() public {
    _psm.setUpgrade();
    assertTrue(_psm.stopped(), 'stopped after setUpgrade');
    assertEq(_psm.upgradeTime(), block.timestamp + 2 days, 'upgradeTime set');

    vm.warp(block.timestamp + 3 days);

    // Seed PSM with some aToken balance.
    _usdcMock.approve(address(_psm), 5_000 * 10 ** 6);
    // But we're stopped + past upgradeTime so deposit should revert (pausable)
    vm.expectRevert(AaveUSDPSMV1.ContractIsPaused.selector);
    _psm.deposit(5_000 * 10 ** 6);

    // Owner can transferToken the gem (aToken) via the upgrade escape hatch.
    // First mint some aToken directly onto PSM for the transfer test.
    _aTokenMock.mint(address(_psm), 1e6);
    _psm.transferToken(address(_aTokenMock), _owner, 1e6);
    assertEq(_aTokenMock.balanceOf(_owner), 1e6, 'owner received aToken via escape hatch');
  }
}
