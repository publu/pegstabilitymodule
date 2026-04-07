// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Script.sol';
import '../contracts/BeefyVaultPSMMainnet.sol';

contract DeployBeefySteakhouseMainnet is Script {
  function run() external {
    vm.startBroadcast();

    BeefyVaultPSMMainnet psm = new BeefyVaultPSMMainnet();
    psm.initialize(
      0x562Ea6FfFD1293b9433E7b81A2682C31892ea013, // Beefy Steakhouse Smokehouse mooToken
      0, // depositFee: 0 bps (per QCI 250)
      30, // withdrawalFee: 30 bps / 0.3% (per QCI 250)
      0x8D6CeBD76f18E1558D4DB88138e2DeFB3909fAD6 // MAI on mainnet
    );

    vm.stopBroadcast();
  }
}
