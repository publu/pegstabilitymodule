// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Script.sol';
import '../contracts/BeefyVaultDDW.sol';

contract DeployBeefyGauntletPrimeBase is Script {
  function run() external {
    vm.startBroadcast();

    BeefyVaultPSM psm = new BeefyVaultPSM();
    psm.initialize(
      0xCCB979379754d605FB4819A3e394D2e4087fC70e, // Beefy Gauntlet Prime USDC (mooMorphoBaseGauntletPrimeUSDC)
      0, // depositFee: 0 bps
      30 // withdrawalFee: 30 bps / 0.3%
    );

    vm.stopBroadcast();
  }
}
