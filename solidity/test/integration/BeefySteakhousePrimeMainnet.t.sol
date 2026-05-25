// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {Test} from 'forge-std/Test.sol';
import {console} from 'forge-std/console.sol';

import {BeefyVaultPSMV2} from 'contracts/BeefyVaultPSM/V2.sol';
import {IBeefy} from 'interfaces/IBeefy.sol';

/// @title BeefySteakhousePrimeMainnetIntegrationTest
/// @notice Fork integration test for the redeployed Ethereum mainnet PSM that
///         wraps the Beefy Steakhouse Prime USDC vault (the "safer collateral"
///         rework — supersedes the never-funded Steakhouse Smokehouse PSM).
///         Validates the REAL new vault wiring that mock tests cannot: that
///         `want()` is canonical USDC, the 18→6 decimal gap resolves to
///         `decimalDifference == 12`, and a deposit/withdraw round-trip works
///         against the live Morpho strategy.
/// @dev Parked out of the default mock loop. Opt in with `RUN_FORK_TESTS=1`
///      plus a working `mainnet` RPC (`MAINNET_RPC`) in `foundry.toml`:
///
///        RUN_FORK_TESTS=1 FOUNDRY_PROFILE=test forge test \
///          --match-contract BeefySteakhousePrimeMainnet -vvv
contract BeefySteakhousePrimeMainnetIntegrationTest is Test {
  // On-chain identities (Ethereum mainnet). GEM verified via Beefy API + cast 2026-05-25.
  address internal constant GEM = 0x48C845d0818bAA17d22b2c0bE41915ec084599bD; // mooMorphoV2EthereumSteakhousePrimeUSDC (18 dec)
  address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // canonical USDC (6 dec)
  address internal constant MAI = 0x8D6CeBD76f18E1558D4DB88138e2DeFB3909fAD6; // MAI on mainnet (18 dec)
  address internal constant MORPHO_VAULT = 0xbeef088055857739C12CD3765F20b7679Def0f51; // Steakhouse Prime USDC Morpho V2 vault (deposit target)

  // Fee config per QCI 250: 0 bps deposit / 30 bps withdrawal.
  uint256 internal constant DEPOSIT_FEE = 0;
  uint256 internal constant WITHDRAWAL_FEE = 30;

  // USDC (FiatTokenV2_2) keeps balances in a mapping at storage slot 9.
  // `deal()` can't auto-locate it through the proxy, and whale balances are
  // fork-block-fragile, so we write the slot directly — block-independent.
  uint256 internal constant USDC_BALANCE_SLOT = 9;

  address internal _user = makeAddr('user');
  address internal _owner = makeAddr('owner');
  address internal _guardian = makeAddr('guardian');

  IERC20 internal _usdc = IERC20(USDC);
  IERC20 internal _mai = IERC20(MAI);
  IBeefy internal _beef = IBeefy(GEM);
  BeefyVaultPSMV2 internal _psm;

  function setUp() public {
    // Fork-only suite. Opt in via RUN_FORK_TESTS=1 so the default `forge test`
    // loop skips it cleanly instead of choking on `deal()` against the real
    // USDC proxy storage.
    if (vm.envOr('RUN_FORK_TESTS', uint256(0)) == 0) {
      vm.skip(true);
      return;
    }
    vm.createSelectFork(vm.rpcUrl('mainnet'));

    // Minimal setup: deploy + initialize + guardian. No token dealing here, so
    // the config-wiring assertions run independently of fork funding mechanics.
    vm.startPrank(_owner);
    _psm = new BeefyVaultPSMV2();
    _psm.initialize(GEM, DEPOSIT_FEE, WITHDRAWAL_FEE, MAI);
    _psm.setGuardian(_guardian, true);
    vm.stopPrank();
  }

  /// @dev Funds the PSM with MAI (deal works for MAI's layout) and the user
  ///      with USDC (whale transfer — deal can't find USDC's proxy slot).
  ///      Called only by tests that exercise the deposit/withdraw flow.
  function _fundForLifecycle() internal {
    deal(address(_mai), address(_psm), 1_000_000 * 10 ** 18);
    bytes32 usdcSlot = keccak256(abi.encode(_user, USDC_BALANCE_SLOT));
    vm.store(USDC, usdcSlot, bytes32(uint256(100_000 * 10 ** 6)));
    assertEq(_usdc.balanceOf(_user), 100_000 * 10 ** 6, 'USDC funded via slot write');
  }

  /// @notice Pure-wiring assertions — the core "is the new vault wired right?"
  ///         check. Independent of vault liquidity, so it always runs on a
  ///         fork regardless of the Steakhouse Prime market's depth.
  function test_mainnet_configWiring() public {
    assertEq(_psm.gem(), GEM, 'gem is the Steakhouse Prime mooToken');
    assertEq(_psm.underlying(), USDC, 'underlying resolves to canonical USDC (want())');
    assertEq(_psm.MAI_ADDRESS(), MAI, 'MAI address is mainnet MAI');
    assertEq(_psm.decimalDifference(), 12, 'decimalDifference is 18 (mooToken) - 6 (USDC)');
    assertEq(_psm.depositFee(), DEPOSIT_FEE, 'deposit fee 0 bps per QCI 250');
    assertEq(_psm.withdrawalFee(), WITHDRAWAL_FEE, 'withdrawal fee 30 bps per QCI 250');
  }

  /// @notice Full lifecycle against the live Beefy/Morpho strategy: deposit →
  ///         scheduleWithdraw → withdraw → second schedule → evacuate →
  ///         claimRefund. Amounts kept modest (the Steakhouse Prime vault is
  ///         freshly seeded) so withdrawal liquidity is realistic.
  function test_mainnet_fullLifecycle() public {
    // The Beefy vault wraps the Steakhouse Prime Morpho V2 vault, which is
    // freshly created and may not yet be activated for deposits. Probe it; if
    // deposits aren't live, skip rather than fail — this test validates the
    // full lifecycle the moment the underlying vault goes live, and documents
    // (via the skip) that funding the PSM is blocked until activation.
    (bool depositsLive,) =
      MORPHO_VAULT.staticcall(abi.encodeWithSignature('previewDeposit(uint256)', uint256(1_000_000)));
    if (!depositsLive) {
      console.log(
        'SKIP: Steakhouse Prime Morpho vault not yet activated for deposits (previewDeposit reverts). Rerun after Beefy/Steakhouse activates the underlying vault.'
      );
      vm.skip(true);
      return;
    }

    _fundForLifecycle();

    // --- deposit ---
    uint256 depositAmount = 1000 * 10 ** 6; // 1,000 USDC
    vm.startPrank(_user);
    _usdc.approve(address(_psm), depositAmount);

    uint256 userMaiBefore = _mai.balanceOf(_user);
    uint256 userUsdcBefore = _usdc.balanceOf(_user);
    _psm.deposit(depositAmount);

    uint256 depositFee = _psm.calculateFee(depositAmount, true);
    uint256 expectedMAI = (depositAmount - depositFee) * 10 ** 12;
    assertEq(_mai.balanceOf(_user), userMaiBefore + expectedMAI, 'MAI paid to user');
    assertEq(_usdc.balanceOf(_user), userUsdcBefore - depositAmount, 'USDC pulled from user');
    assertGt(_beef.balanceOf(address(_psm)), 0, 'PSM holds Beefy vault shares after deposit');

    // --- scheduleWithdraw (3-day lock) ---
    uint256 withdrawMAI = 100 * 10 ** 18;
    _mai.approve(address(_psm), withdrawMAI);
    _psm.scheduleWithdraw(withdrawMAI);
    assertEq(_psm.withdrawalEpoch(_user), block.timestamp + 3 days, 'epoch is 3 days out');
    vm.stopPrank();

    // --- execute scheduled withdraw after the delay ---
    vm.warp(block.timestamp + 3 days + 1);
    vm.prank(_user);
    _psm.withdraw();
    uint256 expectedPayout = 100 * 10 ** 6 - _psm.calculateFee(100 * 10 ** 6, false);
    assertEq(_usdc.balanceOf(_user), userUsdcBefore - depositAmount + expectedPayout, 'user receives net USDC');

    // --- queue a second withdrawal we will recover via claimRefund ---
    uint256 secondWithdrawMAI = 200 * 10 ** 18;
    vm.startPrank(_user);
    _mai.approve(address(_psm), secondWithdrawMAI);
    _psm.scheduleWithdraw(secondWithdrawMAI);
    vm.stopPrank();

    // --- evacuate (guardian) drains the Beefy vault back to USDC on the PSM ---
    vm.prank(_guardian);
    _psm.evacuateVault();
    assertTrue(_psm.evacuated(), 'evacuated flag set');
    assertGt(_usdc.balanceOf(address(_psm)), 0, 'USDC landed on PSM after evacuate');

    // --- claimRefund returns the queued MAI to the user ---
    uint256 userMaiPreClaim = _mai.balanceOf(_user);
    vm.prank(_user);
    _psm.claimRefund();
    assertEq(_mai.balanceOf(_user), userMaiPreClaim + secondWithdrawMAI, 'user recovers queued MAI');
  }
}
