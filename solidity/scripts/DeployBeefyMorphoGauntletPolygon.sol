// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Script.sol';
import 'contracts/BeefyVaultPSMPoly/V1.sol';

contract MyScript is Script {
  function run() external {
    uint256 deployerPrivateKey = vm.envUint('DEPLOYER_PRIVATE_KEY');

    address gem = 0x28deaAE15B3649B7ab0bB3292D9dc1D0337387F6;
    uint256 depositFee = 0;
    uint256 withdrawalFee = 30;

    vm.startBroadcast(deployerPrivateKey);
    BeefyVaultPSMPoly beefyVaultPSMPoly = new BeefyVaultPSMPoly();
    beefyVaultPSMPoly.initialize(gem, depositFee, withdrawalFee);
    beefyVaultPSMPoly.updateMinimumFees(0,1000000);
    vm.stopBroadcast();

    console.log("Deployed BeefyVaultPSMPoly at:", address(beefyVaultPSMPoly));
    console.log("Initialize with:");
    console.log("  gem:", gem);
    console.log("  depositFee:", depositFee);
    console.log("  withdrawalFee:", withdrawalFee);
  }
}
