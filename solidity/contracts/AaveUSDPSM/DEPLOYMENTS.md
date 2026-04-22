# AaveUSDPSM — deployments

| Version | Source | Chain | Chain ID | Address | Broadcast script | Tx hash | Notes |
|---|---|---|---|---|---|---|---|
| V1 | `V1.sol` | Polygon | 137 | _pending deploy_ | `DeployAaveUSDPolygon.s.sol` | — | aPolUSDCn strategy — replaces `BeefyVaultPSMPoly/V1` at `0x6d01...3453a` once migration lands |

## Versions

- **V1** (`V1.sol`, `contract AaveUSDPSMV1`) — raw Aave V3 aToken strategy with the full V2 safety surface: `evacuateVault`, `sweep`, `claimRefund`, `forceSettle`, multi-guardian, configurable MAI, minimum reserves. Drops share math because the aToken's balance is already denominated in the underlying. Not yet deployed.

## Notes

- `gem` is the aToken. `pool` and `underlying` are derived from the aToken itself at init (`POOL()` / `UNDERLYING_ASSET_ADDRESS()`), so the initializer cannot be mis-wired against a mismatched pair.
- Target Polygon aToken: `0xA4D94019934D8333Ef880ABFFbF2FDd611C762BD` (aPolUSDCn, native USDC at `0x3c49...3359`, pool at `0x794a...14aD`). Verified on-chain 2026-04-22.
- **Migration implication**: `BeefyVaultPSMPoly/V1` holds bridged USDC.e; this PSM expects native USDC. The governance-driven migration must swap USDC.e → USDC before seeding.
- Deploy script runs `AaveUSDPSMPreflight.validateInitParams` in the same `run()` before `vm.startBroadcast`, so mis-wiring aborts the simulation.

_Last updated: 2026-04-22 (contract + tests landed, pending deployment)._
