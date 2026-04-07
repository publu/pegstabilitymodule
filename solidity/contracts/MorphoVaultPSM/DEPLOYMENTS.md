# MorphoVaultPSM — deployments

| Version | Source | Chain | Chain ID | Address | Broadcast script | Tx hash | Notes |
|---|---|---|---|---|---|---|---|
| V1 | `V1.sol` | Base | 8453 | `0x88960e693ce3bd88e8b46450097ab9ec25b6cd4c` | `DeployMorphoGauntlet.sol` | `0x9a5c8ab62ff795a50b91066af8257868b0120bd52823c9c2a88125ec8eab4039` | Gauntlet (Base) |
| V1 | `V1.sol` | Base | 8453 | `0x19286b2786b0abd65334cc054f5763b95fd39022` | `DeployMorphoSteakhouse.sol` | `0xfd54c405df9c4269dedd62c81834aa31d8e9ff04c91f7a3578e10511e813f0fc` | Steakhouse (Base) |
| V1 | `V1.sol` | Polygon | 137 | `0x9ff9cf431e56468f09cb49cad2611a4a9b7070f9` | `DeployMorphoGauntletPolygon.sol` | `0x3d72960ab985c95edb335f6ca0367b50604a2c386cca4659496b2f708d0cb112` | Gauntlet (Polygon) |

## Versions

- **V1** (`V1.sol`, `contract MorphoVaultPSM`) — original Morpho-vault PSM. Base + Polygon deployments. Frozen.
- **V2** (`V2.sol`, `contract MorphoVaultPSMV2`) — adds evacuate/sweep, claimRefund, multi-guardian role, `totalQueuedMAI` exact-owed bookkeeping, dust-withdrawal rejection, RedeemFailed event pinning. **In-development — not yet deployed.** Editable until first deployment.

## Notes

- V2 is the primary subject of the evacuate/sweep work that landed in PR #4 (`publu/pegstabilitymodule#4`). It is currently undeployed.
- Test files for V2: `solidity/test/unit/MorphoVaultPSMEvacuateAndSweep.t.sol`, `solidity/test/integration/MorphoEvacuateSweepIntegration.t.sol`, `solidity/test/invariant/MorphoVaultPSMInvariant.sol`.

_Last updated: 2026-04-07 (post V1/V2 split)._
