// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {Test} from 'forge-std/Test.sol';

import {BeefyVaultPSMV2} from 'contracts/BeefyVaultPSM/V2.sol';
import {IBeefy} from '../../interfaces/IBeefy.sol';
import {MockERC20} from '../mocks/MockERC20.sol';
import {MockBeefyVault} from '../mocks/MockBeefyVault.sol';

/// @title BeefyV2LocalBase
/// @notice Mock-based replacement for `BeefyV2IntegrationBase`. Targets the V2
///         BeefyVaultPSM contract which accepts a configurable MAI address in
///         its `initialize(gem, depositFee, withdrawalFee, maiAddress)` call —
///         so unlike V1, no `vm.etch` at a hardcoded constant is required.
/// @dev Use for tests that exercise V2-only behavior (evacuate/sweep,
///      multi-guardian, minimum reserves, configurable MAI).
contract BeefyV2LocalBase is Test {
  address internal _user = makeAddr('user');
  address internal _owner = makeAddr('owner');
  address internal _beefyWhale = 0x008a74d96d799b0fcfae8462BfFF8C37C7ccc611;

  IERC20 internal _mooToken;
  IERC20 internal _usdbcToken;
  IERC20 internal _maiToken;

  MockERC20 internal _usdbcMock;
  MockERC20 internal _maiMock;
  MockBeefyVault internal _beefyMock;

  IBeefy internal _beefyVault;

  BeefyVaultPSMV2 internal _psm;

  function setUp() public virtual {
    vm.startPrank(_owner);

    _usdbcMock = new MockERC20('USD Base Coin', 'USDbC', 6);
    _maiMock = new MockERC20('Mai Stablecoin', 'MAI', 18);

    _beefyMock = new MockBeefyVault(_usdbcMock, 18, 1e18);

    _usdbcToken = IERC20(address(_usdbcMock));
    _maiToken = IERC20(address(_maiMock));
    _mooToken = IERC20(address(_beefyMock));
    _beefyVault = IBeefy(address(_beefyMock));

    _usdbcMock.mint(_owner, 100_000_000 * 10 ** 6);
    _usdbcMock.mint(_user, 100_000_000 * 10 ** 6);

    _psm = new BeefyVaultPSMV2();
    _maiMock.mint(address(_psm), 100_000_000 * 10 ** 18);
    _psm.initialize(address(_mooToken), 100, 100, address(_maiMock));
    _psm.approveBeef();
  }
}
