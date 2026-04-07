// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Script.sol';
import '../contracts/BeefyVaultDDW.sol';

contract MyScript is Script {
  function run() external {
    uint256 deployerPrivateKey = vm.envUint('DEPLOYER_PRIVATE_KEY');
    console.log('privatekey', deployerPrivateKey);
    vm.startBroadcast(deployerPrivateKey);

    BeefyVaultPSM beefyVaultPSM = new BeefyVaultPSM();
    beefyVaultPSM.initialize(0xD7803d3Bf95517D204CFc6211678cAb223aC4c48, 100, 100);

    vm.stopBroadcast();
  }
}
