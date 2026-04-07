// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Script.sol';
import 'contracts/BeefyVaultPSM/V2.sol';

contract DeployBeefyGauntletMainnet is Script {
  function run() external {
    vm.startBroadcast();

    BeefyVaultPSMV2 psm = new BeefyVaultPSMV2();
    psm.initialize(
      0x16F06dE7F077A95684DBAeEdD15A5808c3E13cD0, // Beefy Gauntlet Frontier mooToken
      0, // depositFee: 0 bps (per QCI 250)
      30, // withdrawalFee: 30 bps / 0.3% (per QCI 250)
      0x8D6CeBD76f18E1558D4DB88138e2DeFB3909fAD6 // MAI on mainnet
    );

    vm.stopBroadcast();
  }
}
