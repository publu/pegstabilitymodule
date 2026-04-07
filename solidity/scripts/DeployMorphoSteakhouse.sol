// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Script.sol';
import '../contracts/MorphoVaultPSM.sol';

contract MyScript is Script {
  function run() external {
    uint256 deployerPrivateKey = vm.envUint('DEPLOYER_PRIVATE_KEY');
    vm.startBroadcast(deployerPrivateKey);

    MorphoVaultPSM morphoVaultPSM = new MorphoVaultPSM();
    morphoVaultPSM.initialize(
      0xbeeF010f9cb27031ad51e3333f9aF9C6B1228183, 0, 30, 0xbf1aeA8670D2528E08334083616dD9C5F3B087aE
    );

    vm.stopBroadcast();
  }
}
