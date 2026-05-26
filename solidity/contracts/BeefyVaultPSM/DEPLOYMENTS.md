# BeefyVaultPSM — deployments

| Version | Source | Chain | Chain ID | Address | Broadcast script | Tx hash | Notes |
|---|---|---|---|---|---|---|---|
| V1 | `V1.sol` | Base | 8453 | `0x0b2661e57d2ed4ed798c00063962fca823ef964a` | `DeployBeefyGauntletPrimeBase.s.sol` | `0x2465f2c74e6bf3697ad5c52fc5e86056607d12a6494a8054914e41875bac7d32` | Gauntlet Prime |
| V1 | `V1.sol` | Base | 8453 | `0x91f8101b155132e405c344514b3b0653afb7ef53` | `DeployBeefyGauntletFrontierBase.s.sol` | `0x4c80a5ae445c9f600905991a33c6c3f5b281ee1eab611165bf371c678bdbefc6` | Gauntlet Frontier |
| V1 | `V1.sol` | Base | 8453 | `0x2ed7b0027a5657b5941e1c6c62ee1522049132f4` | `DeployBeefySteakhouseBase.s.sol` | `0x36e585bda9b847770352eec26895710b043c2eaff58a78eacf20260399c62b54` | Steakhouse |
| V1 | `V1.sol` | Base | 8453 | `0xD7Acff6De10A71710C05132eB771e96630Ae132b` | `DeployDDW.sol` | _(missing in broadcast record)_ | DDW |
| V2 | `V2.sol` | Base | 8453 | `0xDdFfa202E803420803F158Fa7f9A2a66F9453BC6` | `DeployBeefyGauntletPrimeBaseV2.s.sol` | `0x2481d99751736da512a7aee945322158ea0804a3a42f8f25137d022d2c686c87` | Gauntlet Prime |
| V2 | `V2.sol` | Base | 8453 | `0x0D5Fe1c9dd2B77c084D81e770C4351F9a48Facf4` | `DeployBeefyGauntletFrontierBaseV2.s.sol` | `0x15196676aaad05d145e0200d14788c9bccfa8e02d4b103529245c345041e8482` | Gauntlet Frontier |
| V2 | `V2.sol` | Base | 8453 | `0xE0391088854da83822849231c5381A6C5aD98cFD` | `DeployBeefySteakhouseBaseV2.s.sol` | `0x07468d58e2099c2b3b80d4b400eaed378604c7d8dc29af1381d673dfa7470abe` | Steakhouse |
| V2 | `V2.sol` | Ethereum Mainnet | 1 | `0x7a4ddc19530db345f05ffe75b3086b04d3b1d99c` | `DeployBeefySteakhouseMainnet.s.sol` | `0x7ddfda9ff1b9a216356fea2c61b588e73f323e4da5b43e0f27adec86568b81e3` | Steakhouse Smokehouse |

## Versions

- **V1** (`V1.sol`, `contract BeefyVaultPSM`) — original Base-deployed PSM. Hardcoded MAI address. Frozen.
- **V2** (`V2.sol`, `contract BeefyVaultPSMV2`) — adds evacuate/sweep, claimRefund, multi-guardian, forceSettle, configurable MAI address, minimum reserves enforcement, `availableForWithdrawal*` views. Frozen (mainnet-deployed). Originally named `BeefyVaultPSMMainnet`; renamed during the V1/V2 split (chain is not the versioning axis).

## Notes

- V2 is a strict superset of V1's behavior — anything that compiles against V1 should also be deployable against V2 (modulo the new constructor param for MAI address).
- Future Base/Polygon/etc. deployments should default to V2 unless there's a reason to stay on V1.
- New work goes in a fresh `V3.sol` once V2 is in production and a new feature is required.

_Last updated: 2026-04-10 (added V2 Base + corrected mainnet V2 address from broadcast)._
