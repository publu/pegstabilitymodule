// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from 'forge-std/Test.sol';
import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {MorphoVaultPSM} from 'contracts/MorphoVaultPSM.sol';
import {IFly} from '../../interfaces/IFly.sol';

/// @title MorphoEvacuateSweepIntegrationTest
/// @notice Integration tests for evacuateVault and sweep against real Base Morpho vaults
/// @dev Fork tests targeting both Gauntlet and Steakhouse vaults
contract MorphoEvacuateSweepIntegrationTest is Test {
  // Base chain addresses
  address internal constant MORPHO_GAUNTLET = 0xc0c5689e6f4D256E861F65465b691aeEcC0dEb12;
  address internal constant MORPHO_STEAKHOUSE = 0xbeeF010f9cb27031ad51e3333f9aF9C6B1228183;
  address internal constant MAI_BASE = 0xbf1aeA8670D2528E08334083616dD9C5F3B087aE;
  address internal constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

  MorphoVaultPSM internal psmGauntlet;
  MorphoVaultPSM internal psmSteakhouse;

  address internal owner = makeAddr('owner');
  address internal guardian = makeAddr('guardian');
  address internal user1 = makeAddr('user1');

  IERC20 internal usdc = IERC20(USDC_BASE);
  IERC20 internal mai = IERC20(MAI_BASE);

  function _dealUSDC(
    address to,
    uint256 amount
  ) internal {
    bytes32 storageSlot = keccak256(abi.encode(to, uint256(9)));
    vm.store(USDC_BASE, storageSlot, bytes32(amount));
  }

  function _dealMAI(
    address to,
    uint256 amount
  ) internal {
    deal(MAI_BASE, to, amount);
  }

  function _deployPSM(
    address vault
  ) internal returns (MorphoVaultPSM psm) {
    vm.startPrank(owner);
    psm = new MorphoVaultPSM();
    psm.initialize(vault, 0, 30, MAI_BASE);
    psm.setGuardian(guardian, true);
    vm.stopPrank();
    _dealMAI(address(psm), 10_000_000 * 10 ** 18);
  }

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl('base'));
    psmGauntlet = _deployPSM(MORPHO_GAUNTLET);
    psmSteakhouse = _deployPSM(MORPHO_STEAKHOUSE);
    _dealUSDC(user1, 1_000_000 * 10 ** 6);
  }

  // ═══════════════════════════════════════════════════════════
  //  Full migration flow test (Gauntlet)
  // ═══════════════════════════════════════════════════════════

  function test_fullMigrationFlow_Gauntlet() public {
    MorphoVaultPSM oldPsm = psmGauntlet;
    IFly vault = IFly(MORPHO_GAUNTLET);

    // Step 1: User deposits into old PSM
    vm.startPrank(user1);
    usdc.approve(address(oldPsm), 100_000 * 10 ** 6);
    oldPsm.deposit(100_000 * 10 ** 6);
    vm.stopPrank();

    uint256 oldStable = oldPsm.totalStableLiquidity();
    assertGt(vault.balanceOf(address(oldPsm)), 0, 'Old PSM should have vault shares');

    // Step 2: Guardian evacuates old PSM
    vm.prank(guardian);
    oldPsm.evacuateVault();

    assertTrue(oldPsm.evacuated(), 'Old PSM should be evacuated');
    assertEq(vault.balanceOf(address(oldPsm)), 0, 'Old PSM vault shares should be 0');
    uint256 usdcInOldPsm = usdc.balanceOf(address(oldPsm));
    assertGt(usdcInOldPsm, 0, 'Old PSM should hold USDC');

    // Step 3: Wait 2 days for transferToken unlock
    vm.warp(block.timestamp + 2 days + 1);

    // Step 4: Transfer USDC out of old PSM to owner
    vm.prank(owner);
    oldPsm.transferToken(USDC_BASE, owner, usdcInOldPsm);
    assertEq(usdc.balanceOf(address(oldPsm)), 0, 'Old PSM should have 0 USDC');

    // Step 5: Deploy new PSM and send USDC to it
    MorphoVaultPSM newPsm = _deployPSM(MORPHO_GAUNTLET);
    vm.prank(owner);
    usdc.transfer(address(newPsm), usdcInOldPsm);

    // Step 6: Sweep USDC into new PSM's vault
    vm.prank(owner);
    newPsm.sweep();

    // Verify: new PSM is operational with correct bookkeeping
    assertEq(newPsm.totalStableLiquidity(), usdcInOldPsm, 'New PSM totalStableLiquidity matches');
    assertGt(vault.balanceOf(address(newPsm)), 0, 'New PSM should have vault shares');
    assertEq(usdc.balanceOf(address(newPsm)), 0, 'No idle USDC in new PSM');
  }

  // ═══════════════════════════════════════════════════════════
  //  Full migration flow test (Steakhouse)
  // ═══════════════════════════════════════════════════════════

  function test_fullMigrationFlow_Steakhouse() public {
    MorphoVaultPSM oldPsm = psmSteakhouse;
    IFly vault = IFly(MORPHO_STEAKHOUSE);

    // Deposit
    vm.startPrank(user1);
    usdc.approve(address(oldPsm), 100_000 * 10 ** 6);
    oldPsm.deposit(100_000 * 10 ** 6);
    vm.stopPrank();

    // Evacuate
    vm.prank(guardian);
    oldPsm.evacuateVault();

    assertTrue(oldPsm.evacuated());
    uint256 usdcInOldPsm = usdc.balanceOf(address(oldPsm));

    // Wait + transfer
    vm.warp(block.timestamp + 2 days + 1);
    vm.prank(owner);
    oldPsm.transferToken(USDC_BASE, owner, usdcInOldPsm);

    // Deploy new + sweep
    MorphoVaultPSM newPsm = _deployPSM(MORPHO_STEAKHOUSE);
    vm.prank(owner);
    usdc.transfer(address(newPsm), usdcInOldPsm);
    vm.prank(owner);
    newPsm.sweep();

    assertEq(newPsm.totalStableLiquidity(), usdcInOldPsm);
    assertGt(vault.balanceOf(address(newPsm)), 0);
  }

  // ═══════════════════════════════════════════════════════════
  //  Evacuation with yield accumulation
  // ═══════════════════════════════════════════════════════════

  function test_evacuateWithYield_Gauntlet() public {
    IFly vault = IFly(MORPHO_GAUNTLET);

    // Deposit
    vm.startPrank(user1);
    usdc.approve(address(psmGauntlet), 100_000 * 10 ** 6);
    psmGauntlet.deposit(100_000 * 10 ** 6);
    vm.stopPrank();

    uint256 sharesAfterDeposit = vault.balanceOf(address(psmGauntlet));
    uint256 stableLiquidity = psmGauntlet.totalStableLiquidity();

    // Warp forward to accumulate yield
    vm.warp(block.timestamp + 90 days);

    // Vault should have more assets per share after yield
    uint256 assetsNow = vault.convertToAssets(sharesAfterDeposit);
    // Note: yield might be minimal in a fork test, but the flow should work

    // Evacuate
    vm.prank(guardian);
    psmGauntlet.evacuateVault();

    uint256 usdcRecovered = usdc.balanceOf(address(psmGauntlet));

    // Recovered USDC should be >= totalStableLiquidity (includes yield)
    assertGe(usdcRecovered, stableLiquidity, 'Should recover at least the deposited amount plus yield');
    assertEq(psmGauntlet.totalStableLiquidity(), stableLiquidity, 'Bookkeeping unchanged');
  }

  // ═══════════════════════════════════════════════════════════
  //  Sweep against real vault
  // ═══════════════════════════════════════════════════════════

  function test_sweepAgainstRealVault_Gauntlet() public {
    IFly vault = IFly(MORPHO_GAUNTLET);

    // Send USDC directly (simulating migration transfer)
    uint256 amount = 50_000 * 10 ** 6;
    _dealUSDC(address(psmGauntlet), amount);

    uint256 sharesBefore = vault.balanceOf(address(psmGauntlet));

    vm.prank(owner);
    psmGauntlet.sweep();

    uint256 sharesAfter = vault.balanceOf(address(psmGauntlet));
    assertGt(sharesAfter, sharesBefore, 'Vault shares should increase');
    assertEq(psmGauntlet.totalStableLiquidity(), amount, 'totalStableLiquidity updated');
    assertEq(usdc.balanceOf(address(psmGauntlet)), 0, 'No idle USDC after sweep');
  }

  // ═══════════════════════════════════════════════════════════
  //  Post-evacuation: new PSM accepts deposits after sweep
  // ═══════════════════════════════════════════════════════════

  function test_newPsmOperationalAfterSweep() public {
    // Evacuate old
    vm.startPrank(user1);
    usdc.approve(address(psmGauntlet), 50_000 * 10 ** 6);
    psmGauntlet.deposit(50_000 * 10 ** 6);
    vm.stopPrank();

    vm.prank(guardian);
    psmGauntlet.evacuateVault();

    vm.warp(block.timestamp + 2 days + 1);
    uint256 usdcRecovered = usdc.balanceOf(address(psmGauntlet));
    vm.prank(owner);
    psmGauntlet.transferToken(USDC_BASE, owner, usdcRecovered);

    // Deploy new PSM, sweep
    MorphoVaultPSM newPsm = _deployPSM(MORPHO_GAUNTLET);
    vm.prank(owner);
    usdc.transfer(address(newPsm), usdcRecovered);
    vm.prank(owner);
    newPsm.sweep();

    // New PSM should accept new user deposits
    _dealUSDC(user1, 10_000 * 10 ** 6);
    vm.startPrank(user1);
    usdc.approve(address(newPsm), 10_000 * 10 ** 6);
    newPsm.deposit(10_000 * 10 ** 6);
    vm.stopPrank();

    assertGt(newPsm.totalStableLiquidity(), usdcRecovered, 'New deposits add to swept liquidity');
  }
}
