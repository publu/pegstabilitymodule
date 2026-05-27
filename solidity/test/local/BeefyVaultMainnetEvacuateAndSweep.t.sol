// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {BeefyVaultPSMV2} from 'contracts/BeefyVaultPSM/V2.sol';
import {MainnetLocalBase} from './MainnetLocalBase.sol';

contract BeefyVaultPSMV2EvacuateAndSweepRegressionTest is MainnetLocalBase {
  address internal guardian = makeAddr('guardian');

  function setUp() public override {
    super.setUp();
    _psm.setGuardian(guardian, true);
    vm.stopPrank();
  }

  function _depositAs(
    address user,
    uint256 amount
  ) internal {
    _dealToken(address(_usdcToken), user, amount);
    vm.startPrank(user);
    _usdcToken.approve(address(_psm), amount);
    _psm.deposit(amount);
    vm.stopPrank();
  }

  function _scheduleWithdrawAs(
    address user,
    uint256 maiAmount
  ) internal {
    _dealToken(address(_maiToken), user, maiAmount);
    vm.startPrank(user);
    _maiToken.approve(address(_psm), maiAmount);
    _psm.scheduleWithdraw(maiAmount);
    vm.stopPrank();
  }

  function test_withdrawMAI_transfersAllExcessPreEvacuationWhenNothingQueued() public {
    uint256 maiBalance = _maiToken.balanceOf(address(_psm));
    uint256 ownerBefore = _maiToken.balanceOf(_owner);

    vm.prank(_owner);
    _psm.withdrawMAI();

    assertEq(
      _maiToken.balanceOf(_owner) - ownerBefore, maiBalance, 'Owner should receive all MAI when nothing is queued'
    );
    assertEq(_maiToken.balanceOf(address(_psm)), 0, 'PSM should hold no MAI when nothing is queued');
  }

  function test_withdrawMAI_protectsQueuedMAIPreEvacuation() public {
    _depositAs(_user, 100_000 * 10 ** 6);

    uint256 withdrawMAI = 40_000 * 10 ** 18;
    _scheduleWithdrawAs(_user, withdrawMAI);

    vm.prank(_owner);
    _psm.withdrawMAI();

    assertEq(_maiToken.balanceOf(address(_psm)), withdrawMAI, 'Queued MAI must remain before evacuation');

    vm.prank(guardian);
    _psm.evacuateVault();

    uint256 userMaiBefore = _maiToken.balanceOf(_user);
    vm.prank(_user);
    _psm.claimRefund();

    assertEq(_maiToken.balanceOf(_user), userMaiBefore + withdrawMAI, 'User should still claim the full queued refund');
  }

  function test_transferToken_protectsQueuedMAIPreEvacuation() public {
    _depositAs(_user, 100_000 * 10 ** 6);

    uint256 withdrawMAI = 40_000 * 10 ** 18;
    _scheduleWithdrawAs(_user, withdrawMAI);

    uint256 psmMaiBalance = _maiToken.balanceOf(address(_psm));
    uint256 available = psmMaiBalance - withdrawMAI;

    vm.prank(_owner);
    vm.expectRevert(BeefyVaultPSMV2.NotEnoughLiquidity.selector);
    _psm.transferToken(address(_maiToken), _owner, psmMaiBalance);

    vm.prank(_owner);
    _psm.transferToken(address(_maiToken), _owner, available);

    assertEq(_maiToken.balanceOf(address(_psm)), withdrawMAI, 'Queued MAI must remain after owner MAI transfer');
  }

  function test_minimumReserves_doesNotAffectQueuedMAIProtection() public {
    _depositAs(_user, 100_000 * 10 ** 6);
    vm.prank(_owner);
    _psm.setMinimumReserves(10_000 * 10 ** 6);

    uint256 withdrawMAI = 40_000 * 10 ** 18;
    _scheduleWithdrawAs(_user, withdrawMAI);

    vm.prank(_owner);
    _psm.withdrawMAI();

    assertEq(_maiToken.balanceOf(address(_psm)), withdrawMAI, 'Queued MAI protection must ignore minimum reserves');
    assertEq(_psm.minimumReserves(), 10_000 * 10 ** 6, 'Minimum reserves config should remain unchanged');
  }
}
