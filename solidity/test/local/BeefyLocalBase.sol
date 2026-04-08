// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {Test} from 'forge-std/Test.sol';

import {BeefyVaultPSM} from 'contracts/BeefyVaultPSM/V1.sol';
import {IBeefy} from '../../interfaces/IBeefy.sol';
import {MockERC20} from '../mocks/MockERC20.sol';
import {MockBeefyVault} from '../mocks/MockBeefyVault.sol';

/// @title BeefyLocalBase
/// @notice Mock-based replacement for `BeefyIntegrationBase`. Deploys local
///         `MockERC20` instances for USDbC and MAI, a `MockBeefyVault` wrapping
///         the USDbC mock, and a fresh `BeefyVaultPSM/V1` initialized against
///         that vault. No fork, no RPC — this setUp runs in milliseconds.
/// @dev Variable names mirror `BeefyIntegrationBase` so inheriting tests need
///      only change their `is` clause and imports. Decimals mirror Base reality
///      (USDbC = 6, MAI = 18, mooToken = 18) per plan Q6 (mirror real-world).
///      Initial share price is 1e18 per plan Q1 (constructor arg, no default).
contract BeefyLocalBase is Test {
  address internal _user = makeAddr('user');
  address internal _owner = makeAddr('owner');
  // `_beefyWhale` retained for test code that references it, though the mock
  // needs no whale — any address can fund the vault via `simulateYield`.
  address internal _beefyWhale = 0x008a74d96d799b0fcfae8462BfFF8C37C7ccc611;

  // ERC20 variables typed as `IERC20` so existing tests that do
  // `_usdbcToken.balanceOf(...)` or `_mooToken.balanceOf(...)` keep compiling.
  IERC20 internal _mooToken;
  IERC20 internal _usdbcToken;
  IERC20 internal _maiToken;

  // Concrete mock handles for test-only knobs (simulateYield, mint, etc.) — tests
  // that need yield accrual cast through these rather than the IERC20 alias.
  MockERC20 internal _usdbcMock;
  MockERC20 internal _maiMock;
  MockBeefyVault internal _beefyMock;

  // `_beefyVault` kept as an `IBeefy` handle for test code that casts through
  // it (e.g., `_beefyVault.deposit(...)`, `_beefyVault.balance()`). The cast
  // resolves to the same address as `_mooToken`; `MockBeefyVault` responds to
  // the IBeefy method set through ABI dispatch even though it does not
  // formally inherit from the interface.
  IBeefy internal _beefyVault;

  BeefyVaultPSM internal _psm;

  /// @dev `BeefyVaultPSM/V1.sol` declares `MAI_ADDRESS` as a constant at the real
  ///      Base mainnet MAI address (line 9 of V1.sol). We can't change the
  ///      constant per Pablo's named-versions convention, so we place a
  ///      `MockERC20` at that address via `vm.etch` and initialize it in place.
  address internal constant _BASE_MAI = 0xbf1aeA8670D2528E08334083616dD9C5F3B087aE;

  function setUp() public virtual {
    vm.startPrank(_owner);

    // Deploy USDbC mock normally — mirror real Base decimals (USDbC = 6).
    _usdbcMock = new MockERC20('USD Base Coin', 'USDbC', 6);

    // Etch MockERC20 runtime code at the hardcoded MAI address so that every
    // IERC20(MAI_ADDRESS).* call inside the PSM dispatches into our mock.
    // The template deploy gives us a live runtime bytecode to copy.
    MockERC20 _maiTemplate = new MockERC20('Template', 'TMPL', 18);
    vm.etch(_BASE_MAI, address(_maiTemplate).code);
    _maiMock = MockERC20(_BASE_MAI);
    _maiMock.initialize('Mai Stablecoin', 'MAI', 18);

    // Deploy Beefy vault mock wrapping USDbC. mooToken decimals = 18 (matches
    // real Beefy). Initial price per share = 1e18 (clean 1:1, per plan Q1).
    _beefyMock = new MockBeefyVault(_usdbcMock, 18, 1e18);

    // Alias views — variable names mirror `BeefyIntegrationBase` exactly.
    _usdbcToken = IERC20(address(_usdbcMock));
    _maiToken = IERC20(address(_maiMock));
    _mooToken = IERC20(address(_beefyMock));
    _beefyVault = IBeefy(address(_beefyMock));

    // Seed balances — match `BeefyIntegrationBase` amounts exactly.
    _usdbcMock.mint(_owner, 100_000_000 * 10 ** 6);
    _usdbcMock.mint(_user, 100_000_000 * 10 ** 6);

    // Deploy and initialize the PSM.
    _psm = new BeefyVaultPSM();
    _maiMock.mint(address(_psm), 100_000_000 * 10 ** 18);
    _psm.initialize(address(_mooToken), 100, 100);
    _psm.approveBeef();
  }
}
