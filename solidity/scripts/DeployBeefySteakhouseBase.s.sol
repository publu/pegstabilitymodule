// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Script.sol';
import 'contracts/BeefyVaultPSM/V1.sol';

contract DeployBeefySteakhouseBase is Script {
  function run() external {
    vm.startBroadcast();

    BeefyVaultPSM psm = new BeefyVaultPSM();
    psm.initialize(
      0xF1C55b6E063ee90A33FFE62deBe618962bae021e, // Beefy Steakhouse High Yield USDC (mooMorphoBaseSteakhouseHighYieldUSDC)
      0, // depositFee: 0 bps
      30 // withdrawalFee: 30 bps / 0.3%
    );

    vm.stopBroadcast();
  }
}
