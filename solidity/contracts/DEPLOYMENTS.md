# PSM contracts — deployment index

Cross-reference of every PSM contract in `solidity/contracts/`, the versions defined for each, and the chains where each version is live on-chain. Each per-contract folder has its own `DEPLOYMENTS.md` with full per-deployment detail (addresses, broadcast scripts, tx hashes).

## Convention

- Each PSM contract gets its own subfolder (e.g. `BeefyVaultPSM/`).
- Versions are stored as `V<n>.sol` files within that subfolder. The contract symbol inside is `<ContractName>V<n>` (e.g. `BeefyVaultPSMV2`); the V1 file keeps the unsuffixed name for compatibility with the originally-deployed bytecode.
- Each subfolder has a `DEPLOYMENTS.md` mirroring the relevant `broadcast/*/run-latest.json` records in human-readable form.
- A version is **frozen** once any chain has a deployment row for it. Frozen versions must not be edited; new work goes in `V<n+1>.sol`.
- **Folders are not frozen — files are.** A folder may contain a mix of frozen V1 and in-development V2 simultaneously.

## Index

| Contract | Folder | Versions | Frozen | In-development | Chains where deployed |
|---|---|---|---|---|---|
| `BeefyVaultPSM` | [`BeefyVaultPSM/`](./BeefyVaultPSM/DEPLOYMENTS.md) | V1, V2 | V1, V2 | — | Base (V1 ×4), Ethereum Mainnet (V2 ×2) |
| `BeefyVaultPSMPoly` | [`BeefyVaultPSMPoly/`](./BeefyVaultPSMPoly/DEPLOYMENTS.md) | V1 | V1 | — | Polygon (V1 ×1) |
| `MorphoVaultPSM` | [`MorphoVaultPSM/`](./MorphoVaultPSM/DEPLOYMENTS.md) | V1 | V1 | — | Base (V1 ×2), Polygon (V1 ×1) — retired, no new work |
| `DAIVaultPSM` | [`DAIVaultPSM/`](./DAIVaultPSM/DEPLOYMENTS.md) | V1 | V1 | — | Scroll (V1 ×1) |
| `USDCVaultPSM` | [`USDCVaultPSM/`](./USDCVaultPSM/DEPLOYMENTS.md) | V1 | V1 | — | Polygon zkEVM (V1 ×1) |
| `USDCVaultDDW` | [`USDCVaultDDW/`](./USDCVaultDDW/DEPLOYMENTS.md) | V1 | V1 | — | Metis (V1 ×1) |

## Quick stats

- **6 PSM contract families**, **7 distinct versions**, **13 live deployments** across 6 chains.
- **0 in-development versions.** `MorphoVaultPSM/V2.sol` (the evacuate/sweep work from PR #4) was deleted on 2026-04-08 as raw Morpho PSM support is being wound down.

## Out-of-folder files

The following files in `solidity/contracts/` are NOT deployed via this repo and are kept at root rather than in version-folders:

- `EditableERC20.sol` — orphan upstream contract, not compiled by `[profile.test]` and not deployed
- `QiDaoOFT.sol` — orphan upstream contract, requires unbundled `@layerzerolabs/solidity-examples`
- `stableQiVault.sol` — flattened basescan dump pinned to solc `0.8.11`, not compatible with project's `0.8.19`
- `IBeefyVaultDDW.sol` — interface; will be moved into `solidity/interfaces/` as part of a separate cleanup

## Updating this index

When you deploy a new contract version:
1. Add the new row to the per-contract `DEPLOYMENTS.md`.
2. If a new version was promoted from in-development to frozen, update the **Frozen** / **In-development** columns in the table above.
3. Update **Quick stats**.

_Last updated: 2026-04-08 (retired MorphoVaultPSM V2 and raw-Morpho test coverage)._
