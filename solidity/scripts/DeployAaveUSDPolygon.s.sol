// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Script.sol';
import 'contracts/AaveUSDPSM/V1.sol';
import '../scripts/AaveUSDPSMPreflight.sol';

/// @notice Deploy AaveUSDPSMV1 on Polygon (chain ID 137) backed by the
///         aPolUSDCn aToken (Aave V3, native USDC). Fee parameters mirror
///         the retired BeefyVaultPSMPoly Gauntlet deployment per QCI 250.
contract DeployAaveUSDPolygon is Script {
  // Aave V3 Polygon aToken for native USDC ("aPolUSDCn"). Resolved 2026-04-22
  // via `cast call ... UNDERLYING_ASSET_ADDRESS()` on chain 137.
  address internal constant GEM = 0xA4D94019934D8333Ef880ABFFbF2FDd611C762BD;

  // Derived from `aPolUSDCn.UNDERLYING_ASSET_ADDRESS()` — native USDC on Polygon.
  address internal constant EXPECTED_UNDERLYING = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;

  // Derived from `aPolUSDCn.POOL()` — Aave V3 Polygon Pool.
  address internal constant EXPECTED_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;

  // Polygon miMATIC (MAI) canonical address.
  address internal constant MAI = 0xa3Fa99A148fA48D14Ed51d610c367C61876997F1;

  // Fee parameters matching QCI 250 / retired BeefyVaultPSMPoly deployment.
  uint256 internal constant DEPOSIT_FEE_BPS = 0;
  uint256 internal constant WITHDRAWAL_FEE_BPS = 30;

  function run() external {
    // Preflight must run before startBroadcast so the fork is still read-only
    // and the script aborts cleanly on mis-wiring.
    AaveUSDPSMPreflight.validateInitParams(
      GEM,
      EXPECTED_POOL,
      EXPECTED_UNDERLYING,
      DEPOSIT_FEE_BPS,
      WITHDRAWAL_FEE_BPS,
      MAI
    );

    vm.startBroadcast();
    AaveUSDPSMV1 psm = new AaveUSDPSMV1();
    psm.initialize(GEM, DEPOSIT_FEE_BPS, WITHDRAWAL_FEE_BPS, MAI);
    // Match the existing Polygon PSM minimum-fee floor: no deposit min, 1 USDC withdraw min.
    psm.updateMinimumFees(0, 1_000_000);
    vm.stopBroadcast();

    console.log('Deployed AaveUSDPSMV1 at:', address(psm));
    console.log('  gem (aToken):     ', GEM);
    console.log('  pool:             ', psm.pool());
    console.log('  underlying (USDC):', psm.underlying());
    console.log('  MAI_ADDRESS:      ', psm.MAI_ADDRESS());
    console.log('  depositFee (bps): ', psm.depositFee());
    console.log('  withdrawalFee (bps):', psm.withdrawalFee());
  }
}
