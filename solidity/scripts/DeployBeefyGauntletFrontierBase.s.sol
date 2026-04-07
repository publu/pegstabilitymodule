// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Script.sol';
import '../contracts/BeefyVaultDDW.sol';

contract DeployBeefyGauntletFrontierBase is Script {
  function run() external {
    vm.startBroadcast();

    BeefyVaultPSM psm = new BeefyVaultPSM();
    psm.initialize(
      0x83152eE78d8f20Bba134A5FF000D551355Ce3996, // Beefy Gauntlet Frontier USDC (mooMorphoBaseGauntletFrontierUSDC)
      0, // depositFee: 0 bps
      30 // withdrawalFee: 30 bps / 0.3%
    );

    vm.stopBroadcast();
  }
}
