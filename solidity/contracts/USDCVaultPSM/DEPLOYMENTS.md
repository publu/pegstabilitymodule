# USDCVaultPSM — deployments

| Version | Source | Chain | Chain ID | Address | Broadcast script | Tx hash | Notes |
|---|---|---|---|---|---|---|---|
| V1 | `V1.sol` | Polygon zkEVM | 1101 | `0xd7acff6de10a71710c05132eb771e96630ae132b` | `DeployUsdcZkevmVault.s.sol` | `0xfabbfbd207ec69385f77f999b0567f42352e46c0bee9c5425874233fe2d524cd` | zkEVM USDC vault |
| V2 | `V2.sol` | Polygon zkEVM | 1101 | `0xC58F53B445e30826c87AD9cB8Ec2358665C6DAC6` | `DeployUsdcZkevmVaultV2.s.sol` | `0xc46bcf9c8810fff244de6629ebf6a550ec6b2be95c0008a3050fee6cfd0b9581` | One-way `close()` finality. 0 bps fee. Owner = deployer EOA pending multisig handoff. Init tx `0xfa9bfd1db021b14a49dc35f879e72f1685db5fc0704533acca5663bc8880da07`. Block 31655736. Verified on OKLink: [`0xC58F…DAC6`](https://www.oklink.com/polygon-zkevm/address/0xC58F53B445e30826c87AD9cB8Ec2358665C6DAC6). |

## Versions

- **V1** (`V1.sol`, `contract USDCVaultPSM`) — USDC-backed PSM with two-step ownership transfer + cancelUpgrade. Frozen.
- **V2** (`V2.sol`, `contract USDCVaultPSMV2`) — Strict superset of V1 plus the one-way `close()` finality primitive. Adds `closedAt` / `closedReason` storage, `Closed(closedAt, reason)` event, `PSMClosed(uint256)` typed revert, and `whenNotClosed` modifier gating `deposit`, `setUpgrade`, and `cancelUpgrade`. `pausable` remains orthogonal (per-selector, two-way). The `close()` flow is permanent and irreversible — owner MUST be a multisig with quorum ≥ 2 before calling.

## Notes

### ⚠️ Source drift from deployed bytecode

The deployed V1 bytecode does **not** match what `V1.sol` in this repo compiles to. Specifically, the deployed `deposit()` checks `_amount == 0`, while `V1.sol` checks `_amount <= minimumDepositFee`. This is an uncommitted local edit that was broadcast in the 2026-03-06 deploy and never round-tripped back to the repo.

**Practical impact today:** none. `minimumDepositFee` is initialized to `0` and has never been updated on-chain, so `_amount == 0` and `_amount <= minimumDepositFee` are functionally equivalent right now.

**Latent risk:** if governance ever raises `minimumDepositFee` via `updateMinimumFee()`, the deployed contract will still accept dust deposits that the committed source implies are rejected. Security reviewers reading `V1.sol` will audit behavior that is not on-chain.

**Verified on OKLink** using a patched-source submission: [`0xd7acff…132b`](https://www.oklink.com/polygon-zkevm/address/0xd7acff6de10a71710c05132eb771e96630ae132b). Methodology written up at `../../../docs/solutions/best-practices/verifying-drifted-deployed-contracts-2026-04-13.md`.

_Last updated: 2026-04-13 (drift documented, OKLink verification completed)._
