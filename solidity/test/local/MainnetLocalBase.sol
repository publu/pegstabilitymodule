// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {Test} from 'forge-std/Test.sol';

import {BeefyVaultPSMV2} from 'contracts/BeefyVaultPSM/V2.sol';
import {IBeefy} from '../../interfaces/IBeefy.sol';
import {MockERC20} from '../mocks/MockERC20.sol';
import {MockBeefyVault} from '../mocks/MockBeefyVault.sol';

/// @title MainnetLocalBase
/// @notice Mock-based replacement for `MainnetIntegrationBase`. Targets the V2
///         BeefyVaultPSM contract which accepts a configurable MAI address —
///         no `vm.etch` needed. The `_mooTokenAddress()` virtual hook and the
///         MAI whale workaround from the fork version are gone: with mocks
///         there's no storage-layout quirk and no "different vault per test"
///         scenario (the single consumer that used the virtual hook,
///         `SteakhouseMainnet.t.sol`, is deferred to Unit 5 assertion review
///         and can restore the pattern there if needed).
/// @dev `_dealToken` helper is preserved with the same signature as the fork
///      version so dependent tests don't need to be retouched — the body now
///      just calls `.mint()` on the appropriate mock.
contract MainnetLocalBase is Test {
  address internal _user = makeAddr('user');
  address internal _owner = makeAddr('owner');

  IERC20 internal _mooToken;
  IERC20 internal _usdcToken;
  IERC20 internal _maiToken;

  MockERC20 internal _usdcMock;
  MockERC20 internal _maiMock;
  MockBeefyVault internal _beefyMock;

  IBeefy internal _beefyVault;
  BeefyVaultPSMV2 internal _psm;

  /// @notice Mint helper. Signature matches the fork version's `_dealToken`
  ///         so dependent tests don't need to be retouched. Body just routes
  ///         to the appropriate mock's `.mint()`.
  function _dealToken(
    address _token,
    address _to,
    uint256 _amount
  ) internal {
    if (_token == address(_maiToken)) {
      _maiMock.mint(_to, _amount);
    } else if (_token == address(_usdcToken)) {
      _usdcMock.mint(_to, _amount);
    } else {
      // Unknown token — caller is doing something unusual. Fall through to a
      // no-op rather than reverting so existing test code that passes an
      // irrelevant address doesn't break.
    }
  }

  function setUp() public virtual {
    // Deploy underlying mocks (USDC = 6 decimals, MAI = 18 — matches mainnet).
    _usdcMock = new MockERC20('USD Coin', 'USDC', 6);
    _maiMock = new MockERC20('Mai Stablecoin', 'MAI', 18);

    // Deploy Beefy vault mock. mooToken decimals = 18 (matches real Beefy).
    // Initial PPS = 1e18 (clean 1:1, per plan Q1).
    _beefyMock = new MockBeefyVault(_usdcMock, 18, 1e18);

    _usdcToken = IERC20(address(_usdcMock));
    _maiToken = IERC20(address(_maiMock));
    _mooToken = IERC20(address(_beefyMock));
    _beefyVault = IBeefy(address(_beefyMock));

    // Seed USDC for owner and user (100M each).
    _usdcMock.mint(_owner, 100_000_000 * 10 ** 6);
    _usdcMock.mint(_user, 100_000_000 * 10 ** 6);

    // Deploy + fund + init PSM. Previous fork version was capped at 5M MAI
    // because the whale only held ~7M; that limit is gone now.
    vm.startPrank(_owner);
    _psm = new BeefyVaultPSMV2();
    _maiMock.mint(address(_psm), 100_000_000 * 10 ** 18);
    _psm.initialize(address(_mooToken), 100, 100, address(_maiToken));
    _psm.approveBeef();
  }
}
