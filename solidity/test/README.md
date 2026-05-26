# pegstabilitymodule tests

The default test suite is **local** — it runs against in-process mock contracts, not against a forked chain. No RPC keys, no network, sub-second inner loop.

## Layout

```
solidity/test/
├── local/           ← default test suite. Runs via `yarn test`.
│   ├── BeefyLocalBase.sol         fixture: BeefyVaultPSM V1 on Base-like mocks
│   ├── BeefyLocalPoly.sol         fixture: BeefyVaultPSMPoly V1 on Polygon-like mocks
│   ├── BeefyV2LocalBase.sol       fixture: BeefyVaultPSM V2 with configurable MAI
│   ├── MainnetLocalBase.sol       fixture: BeefyVaultPSM V2 "mainnet-style" setup
│   ├── BeefyVaultW.sol            tests against BeefyLocalBase
│   ├── BeefyVaultWP.sol           tests against BeefyLocalPoly
│   ├── BeefyVaultEvacuateAndSweep.t.sol   tests against BeefyV2LocalBase
│   ├── BeefyVaultMainnet.sol      tests against MainnetLocalBase
│   ├── BeefyVaultMainnetEvacuateAndSweep.t.sol   tests against MainnetLocalBase
│   ├── SteakhouseMainnet.t.sol    tests against MainnetLocalBase
│   └── invariants/
│       └── BeefyVaultLocalInvariant.sol    handler + 2 invariant test contracts
├── mocks/           ← mock contracts used by the LocalBases
│   ├── MockERC20.sol              thin wrapper over forge-std's MockERC20
│   ├── MockBeefyVault.sol         IBeefy mock w/ simulateYield + simulateLoss
│   └── MockERC4626Vault.sol       IL2DSR / IFly ERC4626 mock (no current consumer)
├── echidna/         ← Echidna property tests, run via the Echidna CLI, not forge
└── unit/, integration/   ← PARKED fork-based tests (see below)
```

## Running

| Command             | What runs                                    | Needs RPC | Typical time   |
|---------------------|----------------------------------------------|-----------|----------------|
| `yarn test`         | local/ unit + integration tests + invariants | No        | ~1.5s unit / ~80s invariants |
| `yarn test:local`   | same as `yarn test`                          | No        | same           |
| `yarn test:fork`    | parked unit/*.sol tests (DAI/Metis/zkEVM)    | **Yes**   | multiple minutes |
| `yarn test:fork:steakhouse-prime` | Steakhouse Prime mainnet lifecycle fork gate | **Yes** | ~10s after compile |
| `yarn coverage`     | coverage report for local/ suite             | No        | ~10s           |

For a fast save-loop, skip invariants: `yarn test --no-match-path 'solidity/test/local/invariants/**/*.sol'` — finishes in under a second.

## Writing a new test

1. Pick the LocalBase whose PSM you're targeting, or write a new `<Name>LocalBase.sol` if you need a different contract family.
2. Inherit from it — `contract MyTest is BeefyLocalBase { ... }`.
3. Inside test bodies, mint tokens with `_usdbcMock.mint(addr, amount)` instead of `deal()`. `deal()` still works against `MockERC20` (standard ERC20 storage layout) but `.mint()` is clearer.
4. To simulate Beefy yield, call `_beefyMock.simulateYield(amount)` — it inflates the vault's underlying balance without minting shares, raising `getPricePerFullShare()`. `simulateLoss(amount)` does the opposite.
5. Put test files directly under `solidity/test/local/`. Put invariant suites under `solidity/test/local/invariants/`.

## Adding a new mock method

The mocks under `solidity/test/mocks/` implement only the method subset the PSM contracts actually call. If you need a new method (because a new test or a new contract calls it), add it to the existing mock — don't create a second mock. Keep state-changing methods faithful (deposit/withdraw/transfer actually move balances) and view methods trivial (return a constant or a derived value).

## When a contract grows a new external dependency

If a new PSM contract under `solidity/contracts/` starts calling an interface not already in the mock library:
1. Add the interface file under `solidity/interfaces/` if it doesn't exist.
2. Write a new mock under `solidity/test/mocks/` matching the smallest usable surface.
3. Wire the mock into the relevant `<Name>LocalBase.sol` (or write a new LocalBase if the contract family doesn't fit existing ones).
4. Write tests against the new LocalBase.
5. Do not add fork-based tests for new contracts — the local-mock pattern is the convention going forward.

## Hardcoded `MAI_ADDRESS` in V1 contracts

`BeefyVaultPSM/V1.sol` and `BeefyVaultPSMPoly/V1.sol` have `address public constant MAI_ADDRESS = 0x...` declared at line 9. Pablo's named-versions convention forbids modifying deployed contract source. The LocalBases work around this with `vm.etch`: deploy a `MockERC20` template to get live runtime bytecode, etch that bytecode at the hardcoded MAI address, then call `initialize()` on the etched contract. Every `IERC20(MAI_ADDRESS).*` dispatch inside V1 then resolves to our mock. See `BeefyLocalBase.sol` and `BeefyLocalPoly.sol` for the pattern.

V2 and later PSM contracts (`BeefyVaultPSM/V2.sol`, `DAIVaultPSM/V1.sol` indirectly) take the MAI address as an `initialize` argument — no etch needed, they just get passed `address(_maiMock)` directly.

## Parked fork-based tests

The following test files still fork real chains via `[profile.test]`:

- `unit/DAIVaultW.sol` + `integration/DAIIntegrationBase.sol` (Linea / WDAI)
- `unit/USDCVaultW.sol`, `unit/USDCVaultW_Extended.sol` + `integration/MetisIntegrationBase.sol` (Metis)
- `unit/USDCVaultPSM.sol` + `integration/ZkevmIntegrationBase.sol` (Polygon zkEVM)

These test the `DAIVaultPSM`, `USDCVaultDDW`, and `USDCVaultPSM` contracts. QiDAO is not actively putting engineering resources into those chains, so the tests were intentionally **not** converted to local mocks during the main refactor. They remain as fork-based tests so that coverage isn't lost outright.

They do **NOT** run in CI. To exercise them manually, ensure the relevant RPC endpoints in `foundry.toml` `[rpc_endpoints]` resolve (Linea, Metis, zkEVM use hardcoded public RPCs; mainnet is optional since none of the parked fixtures require it) and run:

```bash
yarn test:fork
```

If one of those chains becomes active work again, convert its fixture to a LocalBase using the pattern from Unit 3/4 of `docs/plans/2026-04-08-002-refactor-isolate-fork-and-fuzz-tests-plan.md`, and delete the corresponding `unit/*.sol` + `integration/*IntegrationBase.sol` files.

## Steakhouse Prime fork gate

`integration/BeefySteakhousePrimeMainnet.t.sol` is the deploy gate for the Ethereum mainnet BeefyVaultPSMV2 / Steakhouse Prime configuration. It runs under the focused `steakhouse-prime` Foundry profile, which compiles only the deploy surface with solc 0.8.24, Cancun EVM semantics, and 10,000 optimizer runs. Cancun is required because the live downstream Morpho Vault V2 dependency uses transient storage, and the deploy artifact should match the fork gate's execution requirements.

For this deploy, `BeefyVaultPSMV2.UPGRADE_DELAY()` is 72 hours (`3 days`) so the privileged upgrade/transfer window is not shorter than the user withdrawal delay.

Ownership is two-step for this deploy surface. The deployer starts as `owner`, calls `transferOwnership(safe)`, and the Safe must call `acceptOwnership()` before any MAI funding/opening-access transaction.

```bash
yarn test:fork:steakhouse-prime
```

This gate should pass with `0 skipped` before funding/opening the PSM.

The non-broadcast deploy rehearsal uses the same profile:

```bash
yarn deploy:mainnet:steakhouse-prime:dry-run
```

## Invariants

`solidity/test/local/invariants/BeefyVaultLocalInvariant.sol` contains `PSMHandler` plus two invariant test contracts: `BeefyVaultMainnetInvariantTest` (positive `minimumReserves`) and `BeefyVaultMainnetInvariantZeroReserves` (backward-compat case). Both inherit `StdInvariant` and run against mock-based PSM deployments.

The handler exposes five fuzzable selectors: `deposit`, `scheduleWithdraw`, `withdraw`, `warpTime`, and `simulateYield`. The `simulateYield` selector exercises share-price drift so the invariants observe PSM behavior across realistic state trajectories, not just user flow orderings.

Running invariants: `yarn test` (included by default) or scoped with `--match-path 'solidity/test/local/invariants/**/*.sol'`. Budget ~80s of wall time per run for the default forge fuzz settings.

To verify invariants still catch real bugs (the plan's G3 goal), inject a deliberate mutation into `solidity/contracts/BeefyVaultPSM/V2.sol` — for example, drop the `- minimumReserves` from `availableForWithdrawal()`'s computation — run the invariant suite, confirm `invariant_availableForWithdrawalCorrect` fails, then revert the mutation. The plan's Unit 6 commit documents a recent execution of this check.

## Echidna

The files under `solidity/test/echidna/` are property tests consumed by the Echidna fuzzer CLI, not by forge. They run on a separate schedule (manual for now). Refactoring them to use the local mock library is out of scope for this plan — see `docs/plans/2026-04-08-002-refactor-isolate-fork-and-fuzz-tests-plan.md` Future Work section.
