# MorphoVaultPSM — deployments

| Version | Source | Chain | Chain ID | Address | Broadcast script | Tx hash | Notes |
|---|---|---|---|---|---|---|---|
| V1 | `V1.sol` | Base | 8453 | `0x88960e693ce3bd88e8b46450097ab9ec25b6cd4c` | `DeployMorphoGauntlet.sol` | `0x9a5c8ab62ff795a50b91066af8257868b0120bd52823c9c2a88125ec8eab4039` | Gauntlet (Base) |
| V1 | `V1.sol` | Base | 8453 | `0x19286b2786b0abd65334cc054f5763b95fd39022` | `DeployMorphoSteakhouse.sol` | `0xfd54c405df9c4269dedd62c81834aa31d8e9ff04c91f7a3578e10511e813f0fc` | Steakhouse (Base) |
| V1 | `V1.sol` | Polygon | 137 | `0x9ff9cf431e56468f09cb49cad2611a4a9b7070f9` | `DeployMorphoGauntletPolygon.sol` | `0x3d72960ab985c95edb335f6ca0367b50604a2c386cca4659496b2f708d0cb112` | Gauntlet (Polygon) |

## Versions

- **V1** (`V1.sol`, `contract MorphoVaultPSM`) — original Morpho-vault PSM. Base + Polygon deployments. Frozen baseline. No active test coverage — raw Morpho PSM support is being wound down and `V1.sol` remains only because it is live on-chain.

## Notes

- **Raw Morpho PSM is being retired.** `V2.sol` (the evacuate/sweep work from PR #4) was deleted along with all Morpho-related test files on 2026-04-08. `V1.sol` stays because the three deployments listed above are live and cannot be rolled back.
- Do not add new Morpho PSM versions to this folder. Any future Morpho integration should go through a new contract family.
- No test files exist for this contract. If a production incident requires touching `V1.sol`, write fresh tests as part of that incident work.

_Last updated: 2026-04-08 (raw Morpho PSM retired, V2 + test files deleted)._
