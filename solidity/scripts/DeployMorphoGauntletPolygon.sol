// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Script.sol';
import 'contracts/MorphoVaultPSM/V1.sol';
import '../scripts/MorphoVaultPSMPreflight.sol';

contract MyScript is Script {
  function run() external {
    uint256 deployerPrivateKey = vm.envUint('DEPLOYER_PRIVATE_KEY');

    address gem = 0x781FB7F6d845E3bE129289833b04d43Aa8558c42;
    uint256 depositFee = 0;
    uint256 withdrawalFee = 30;
    address maiAddress = 0xa3Fa99A148fA48D14Ed51d610c367C61876997F1;

    // Run preflight checks before broadcast to allow proper fork state access
    MorphoVaultPSMPreflight.validateInitParams(gem, depositFee, withdrawalFee, maiAddress);

    vm.startBroadcast(deployerPrivateKey);
    MorphoVaultPSM morphoVaultPSM = new MorphoVaultPSM();
    morphoVaultPSM.initialize(gem, depositFee, withdrawalFee, maiAddress);
    vm.stopBroadcast();
  }
}
