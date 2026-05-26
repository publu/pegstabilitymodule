# DAIVaultPSM — deployments

| Version | Source | Chain | Chain ID | Address | Broadcast script | Tx hash | Notes |
|---|---|---|---|---|---|---|---|
| V1 | `V1.sol` | Scroll | 534352 | `0xF488F57D441A7CC14E67bdFE84BAC106517FfEbF` | `DeployScrollDW.sol` | `0xb9c34ab67306d76ef9600a0094269353f5f7927fdb2c3071af115468f322fe84` | Scroll DAI vault |

## Versions

- **V1** (`V1.sol`, `contract DAIVaultPSM`) — DAI-backed PSM variant deployed on Scroll. Was named `DAIVaultDW.sol` before the V1/V2 split refactor. Frozen.

## Notes

- No V2 yet. The Beefy/Morpho evacuate/sweep work in PR #4 did not touch this contract.

_Last updated: 2026-04-07 (post V1/V2 split)._
