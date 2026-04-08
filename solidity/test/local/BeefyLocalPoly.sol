// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {Test} from 'forge-std/Test.sol';

import {BeefyVaultPSMPoly} from 'contracts/BeefyVaultPSMPoly/V1.sol';
import {IBeefy} from '../../interfaces/IBeefy.sol';
import {MockERC20} from '../mocks/MockERC20.sol';
import {MockBeefyVault} from '../mocks/MockBeefyVault.sol';

/// @title BeefyLocalPoly
/// @notice Mock-based replacement for `BeefyIntegrationPoly`. Same structure as
///         `BeefyLocalBase` but targets `BeefyVaultPSMPoly/V1` and uses the
///         Polygon MAI constant. `MockERC20` runtime code is etched at the
///         hardcoded Polygon MAI address to satisfy `IERC20(MAI_ADDRESS).*`
///         calls inside the PSM without modifying V1 source.
contract BeefyLocalPoly is Test {
  address internal _user = makeAddr('user');
  address internal _owner = makeAddr('owner');
  address internal _beefyWhale = 0xcFae084c26582c38c2e9Bfb92Da7d54f842A7A5f;

  IERC20 internal _mooToken;
  IERC20 internal _usdbcToken;
  IERC20 internal _maiToken;

  MockERC20 internal _usdbcMock;
  MockERC20 internal _maiMock;
  MockBeefyVault internal _beefyMock;

  IBeefy internal _beefyVault;

  BeefyVaultPSMPoly internal _psm;

  /// @dev `BeefyVaultPSMPoly/V1.sol` line 9 hardcodes `MAI_ADDRESS` as the
  ///      Polygon MAI (miMATIC) contract. Same etch-at-address trick as
  ///      `BeefyLocalBase`, just a different hardcoded constant.
  address internal constant _POLY_MAI = 0xa3Fa99A148fA48D14Ed51d610c367C61876997F1;

  function setUp() public {
    vm.startPrank(_owner);

    // Deploy USDC.e mock (bridged USDC on Polygon, 6 decimals).
    _usdbcMock = new MockERC20('USD Coin (PoS)', 'USDC.e', 6);

    // Etch MockERC20 runtime code at the hardcoded Polygon MAI address so
    // every `IERC20(MAI_ADDRESS).*` dispatch inside `BeefyVaultPSMPoly`
    // resolves to our mock.
    MockERC20 _maiTemplate = new MockERC20('Template', 'TMPL', 18);
    vm.etch(_POLY_MAI, address(_maiTemplate).code);
    _maiMock = MockERC20(_POLY_MAI);
    _maiMock.initialize('Mai Stablecoin', 'miMATIC', 18);

    // Beefy mooToken mock wrapping USDC.e. mooToken decimals = 18 (matches
    // real Polygon mooTokens). Initial PPS = 1e18 (clean 1:1, per plan Q1).
    _beefyMock = new MockBeefyVault(_usdbcMock, 18, 1e18);

    _usdbcToken = IERC20(address(_usdbcMock));
    _maiToken = IERC20(address(_maiMock));
    _mooToken = IERC20(address(_beefyMock));
    _beefyVault = IBeefy(address(_beefyMock));

    _usdbcMock.mint(_owner, 100_000_000 * 10 ** 6);
    _usdbcMock.mint(_user, 100_000_000 * 10 ** 6);

    _psm = new BeefyVaultPSMPoly();
    _maiMock.mint(address(_psm), 100_000_000 * 10 ** 18);
    _psm.initialize(address(_mooToken), 100, 100);
    _psm.approveBeef();
  }
}
