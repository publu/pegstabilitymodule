// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Script.sol';
import {USDCVaultPSMV2} from 'contracts/USDCVaultPSM/V2.sol';

/// @title DeployUsdcZkevmVaultV2
/// @notice Deploys USDCVaultPSMV2 to Polygon zkEVM alongside the existing V1
///         (`0xd7acff6de10a71710c05132eb771e96630ae132b`). V1 stays live; V2 is
///         the successor that ships the one-way `close()` finality primitive.
/// @dev    Ownership stays with the deploying EOA at deploy time. Multisig
///         transferOwnership/acceptOwnership is a follow-up tx tracked
///         separately. Until that handoff completes, do NOT call `close()` —
///         the runbook's "owner = multisig with quorum >= 2" precondition is
///         not yet satisfied.
contract DeployUsdcZkevmVaultV2 is Script {
  function run() external {
    vm.startBroadcast();

    USDCVaultPSMV2 psm = new USDCVaultPSMV2();
    address maiAddress = 0x615B25500403Eb688Be49221b303084D9Cf0E5B4; // MAI on Polygon zkEVM
    address usdcAddress = 0x37eAA0eF3549a5Bb7D431be78a3D99BD360d19e5; // USDC on Polygon zkEVM
    psm.initialize(0, maiAddress, usdcAddress); // 0 bps deposit fee, matches V1

    vm.stopBroadcast();
  }
}
