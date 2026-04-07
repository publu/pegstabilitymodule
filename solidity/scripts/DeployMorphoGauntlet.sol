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
      0xc0c5689e6f4D256E861F65465b691aeEcC0dEb12, 0, 30, 0xbf1aeA8670D2528E08334083616dD9C5F3B087aE
    );

    vm.stopBroadcast();
  }
}
