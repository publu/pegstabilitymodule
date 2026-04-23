# AaveUSDPSM — deployments

| Version | Source | Chain | Chain ID | Address | Broadcast script | Tx hash | Notes |
|---|---|---|---|---|---|---|---|
| V1 | `V1.sol` | Polygon | 137 | `0x4a00e5dea744b71f866c40a00e7190651c89bb0a` | `DeployAaveUSDPolygon.s.sol` | — | aPolUSDCn strategy — replaces `BeefyVaultPSMPoly/V1` at `0x6d01...3453a` once migration lands |

## Versions

- **V1** (`V1.sol`, `contract AaveUSDPSMV1`) — raw Aave V3 aToken strategy with the full V2 safety surface: `evacuateVault`, `sweep`, `claimRefund`, `forceSettle`, multi-guardian, configurable MAI, minimum reserves. Drops share math because the aToken's balance is already denominated in the underlying. Deployed 2026-04-22 on Polygon mainnet.

## Notes

- `gem` is the aToken. `pool` and `underlying` are derived from the aToken itself at init (`POOL()` / `UNDERLYING_ASSET_ADDRESS()`), so the initializer cannot be mis-wired against a mismatched pair.
- Target Polygon aToken: `0xA4D94019934D8333Ef880ABFFbF2FDd611C762BD` (aPolUSDCn, native USDC at `0x3c49...3359`, pool at `0x794a...14aD`). Verified on-chain 2026-04-22.
- **Migration implication**: `BeefyVaultPSMPoly/V1` holds bridged USDC.e; this PSM expects native USDC. The governance-driven migration must swap USDC.e → USDC before seeding.
- Deploy script runs `AaveUSDPSMPreflight.validateInitParams` in the same `run()` before `vm.startBroadcast`, so mis-wiring aborts the simulation.

## Init parameters (as broadcast)

- `minimumDepositFee = 0` — deploy intentionally sets this to `0` so dust-sized deposits aren't rejected at boot. The source constant `1_000_000` in the `constructor` body was overridden in the broadcast session via a local edit; the repo source now matches (`V1.sol`).

_Last updated: 2026-04-22 (deployed to Polygon mainnet at `0x4a00e5de…bb0a`)._
