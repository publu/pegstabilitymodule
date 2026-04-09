# BeefyVaultPSM — deployments

| Version | Source | Chain | Chain ID | Address | Broadcast script | Tx hash | Notes |
|---|---|---|---|---|---|---|---|
| V1 | `V1.sol` | Base | 8453 | `0x0b2661e57d2ed4ed798c00063962fca823ef964a` | `DeployBeefyGauntletPrimeBase.s.sol` | `0x2465f2c74e6bf3697ad5c52fc5e86056607d12a6494a8054914e41875bac7d32` | Gauntlet Prime |
| V1 | `V1.sol` | Base | 8453 | `0x91f8101b155132e405c344514b3b0653afb7ef53` | `DeployBeefyGauntletFrontierBase.s.sol` | `0x4c80a5ae445c9f600905991a33c6c3f5b281ee1eab611165bf371c678bdbefc6` | Gauntlet Frontier |
| V1 | `V1.sol` | Base | 8453 | `0x2ed7b0027a5657b5941e1c6c62ee1522049132f4` | `DeployBeefySteakhouseBase.s.sol` | `0x36e585bda9b847770352eec26895710b043c2eaff58a78eacf20260399c62b54` | Steakhouse |
| V1 | `V1.sol` | Base | 8453 | `0xD7Acff6De10A71710C05132eB771e96630Ae132b` | `DeployDDW.sol` | _(missing in broadcast record)_ | DDW |
| V2 | `V2.sol` | Ethereum Mainnet | 1 | `0x2bec9d381e1081185f4f27bd0b9dd90a5b08826b` | `DeployBeefySteakhouseMainnet.s.sol` | `0x700b14b4991e4b1ec383597919efe5221c519ae4d97fbafcaa70768a39ee1c13` | Steakhouse |

## Versions

- **V1** (`V1.sol`, `contract BeefyVaultPSM`) — original Base-deployed PSM. Hardcoded MAI address. Frozen.
- **V2** (`V2.sol`, `contract BeefyVaultPSMV2`) — adds evacuate/sweep, claimRefund, multi-guardian, forceSettle, configurable MAI address, minimum reserves enforcement, `availableForWithdrawal*` views. Frozen (mainnet-deployed). Originally named `BeefyVaultPSMMainnet`; renamed during the V1/V2 split (chain is not the versioning axis).

## Notes

- V2 is a strict superset of V1's behavior — anything that compiles against V1 should also be deployable against V2 (modulo the new constructor param for MAI address).
- Future Base/Polygon/etc. deployments should default to V2 unless there's a reason to stay on V1.
- New work goes in a fresh `V3.sol` once V2 is in production and a new feature is required.

_Last updated: 2026-04-07 (post V1/V2 split)._
