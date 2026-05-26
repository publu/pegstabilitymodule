# USDCVaultDDW — deployments

| Version | Source | Chain | Chain ID | Address | Broadcast script | Tx hash | Notes |
|---|---|---|---|---|---|---|---|
| V1 | `V1.sol` | Metis | 1088 | `0x7a802aab2185480dfe16d936462fd3becceecb00` | `DeployUsdcMetisVault.s.sol` | `0x14248613f29a8605f66ae2d7457da69b7796018c3eac6a9c52844ccd0a9773ca` | Metis USDC vault |

## Versions

- **V1** (`V1.sol`, `contract USDCVaultDDW`) — Metis USDC vault deposit/withdraw contract with configurable MAI + USDC addresses. Frozen.

## Notes

- No V2 yet. The Beefy/Morpho evacuate/sweep work in PR #4 did not touch this contract.

_Last updated: 2026-04-07 (post V1/V2 split)._
