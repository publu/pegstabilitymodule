// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Script.sol';
import 'contracts/BeefyVaultPSM/V2.sol';

contract DeployBeefySteakhousePrimeMainnet is Script {
  function run() external {
    vm.startBroadcast();

    BeefyVaultPSMV2 psm = new BeefyVaultPSMV2();
    psm.initialize(
      0x48C845d0818bAA17d22b2c0bE41915ec084599bD, // Beefy Steakhouse Prime USDC (mooMorphoV2EthereumSteakhousePrimeUSDC), wraps Morpho Steakhouse Prime USDC vault
      0, // depositFee: 0 bps (per QCI 250)
      30, // withdrawalFee: 30 bps / 0.3% (per QCI 250)
      0x8D6CeBD76f18E1558D4DB88138e2DeFB3909fAD6 // MAI on mainnet
    );

    vm.stopBroadcast();
  }
}
