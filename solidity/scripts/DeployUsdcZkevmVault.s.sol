// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Script.sol';
import {USDCVaultPSM} from 'contracts/USDCVaultPSM/V1.sol';

contract DeployUsdcZkevmVault is Script {
  function run() external {
    vm.startBroadcast();

    USDCVaultPSM psm = new USDCVaultPSM();
    address maiAddress = 0x615B25500403Eb688Be49221b303084D9Cf0E5B4; // MAI on Polygon zkEVM
    address usdcAddress = 0x37eAA0eF3549a5Bb7D431be78a3D99BD360d19e5; // USDC on Polygon zkEVM
    psm.initialize(0, maiAddress, usdcAddress); // 0 bps deposit fee

    vm.stopBroadcast();
  }
}
