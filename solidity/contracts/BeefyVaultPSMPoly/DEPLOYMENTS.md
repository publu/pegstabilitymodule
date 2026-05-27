# BeefyVaultPSMPoly — deployments

| Version | Source | Chain | Chain ID | Address | Broadcast script | Tx hash | Notes |
|---|---|---|---|---|---|---|---|
| V1 | `V1.sol` | Polygon | 137 | `0x6d01fbf0f5d085209aeefab3ab8e31298183453a` | `DeployBeefyMorphoGauntletPolygon.sol` | `0x6ec3e5a1a748e583c46293e9dccf5e2f0fb868ba069c2e277feaf344a81b16c8` | Gauntlet (Polygon Compound USDC.e PSM) |

## Versions

- **V1** (`V1.sol`, `contract BeefyVaultPSMPoly`) — Polygon-specific Beefy PSM variant (Compound USDC.e). Was named `BeefyVaultDDWPoly.sol` before the V1/V2 split refactor. Frozen.

## Notes

- No V2 yet. The Beefy evacuate/sweep work in PR #4 did not touch this contract.
- If/when this contract gets the evacuate/sweep treatment, port the relevant changes from `BeefyVaultPSM/V2.sol` and add a `V2.sol` here.

_Last updated: 2026-04-07 (post V1/V2 split)._
