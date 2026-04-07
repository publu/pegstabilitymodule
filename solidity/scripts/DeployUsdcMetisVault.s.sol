// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Script.sol';
import {USDCVaultDDW} from '../contracts/USDCVaultDDW.sol';

contract MyScript is Script {
  function run() external {
    uint256 deployerPrivateKey = vm.envUint('DEPLOYER_PRIVATE_KEY');
    vm.startBroadcast(deployerPrivateKey);

    USDCVaultDDW usdcVaultDDW = new USDCVaultDDW();
    address maiAddress = 0xdFA46478F9e5EA86d57387849598dbFB2e964b02; // MAI on Metis
    address usdcAddress = 0xEA32A96608495e54156Ae48931A7c20f0dcc1a21; // USDC on Metis
    usdcVaultDDW.initialize(0, 30, maiAddress, usdcAddress);

    vm.stopBroadcast();
  }
}
