# USDCVaultPSM — deployments

| Version | Source | Chain | Chain ID | Address | Broadcast script | Tx hash | Notes |
|---|---|---|---|---|---|---|---|
| V1 | `V1.sol` | Polygon zkEVM | 1101 | `0xd7acff6de10a71710c05132eb771e96630ae132b` | `DeployUsdcZkevmVault.s.sol` | `0xfabbfbd207ec69385f77f999b0567f42352e46c0bee9c5425874233fe2d524cd` | zkEVM USDC vault |

## Versions

- **V1** (`V1.sol`, `contract USDCVaultPSM`) — USDC-backed PSM with two-step ownership transfer + cancelUpgrade. Frozen.

## Notes

- No V2 yet. The Beefy/Morpho evacuate/sweep work in PR #4 did not touch this contract.

_Last updated: 2026-04-07 (post V1/V2 split)._
