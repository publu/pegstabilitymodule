// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {Test} from 'forge-std/Test.sol';

import {AaveUSDPSMV1} from 'contracts/AaveUSDPSM/V1.sol';
import {MockERC20} from '../mocks/MockERC20.sol';
import {MockAavePool} from '../mocks/MockAavePool.sol';
import {MockAToken} from '../mocks/MockAToken.sol';

/// @title AaveLocalPoly
/// @notice Mock-based fixture for `AaveUSDPSMV1` targeting the Polygon
///         token layout: native USDC (6 decimals) + `aPolUSDCn` aToken
///         (6 decimals) + miMATIC MAI (18 decimals). V1 takes the MAI
///         address via initializer so no `vm.etch` trick is required.
contract AaveLocalPoly is Test {
  address internal _user = makeAddr('user');
  address internal _owner = makeAddr('owner');

  MockERC20 internal _usdcMock;
  MockERC20 internal _maiMock;
  MockAToken internal _aTokenMock;
  MockAavePool internal _poolMock;

  IERC20 internal _usdcToken;
  IERC20 internal _maiToken;
  IERC20 internal _aToken;

  AaveUSDPSMV1 internal _psm;

  function setUp() public virtual {
    vm.startPrank(_owner);

    _usdcMock = new MockERC20('USD Coin', 'USDC', 6);
    _maiMock = new MockERC20('Mai Stablecoin', 'MAI', 18);

    // Pool must exist before the aToken (aToken stores POOL as immutable).
    _poolMock = new MockAavePool(_usdcMock);
    _aTokenMock = new MockAToken('Aave Polygon USDCn', 'aPolUSDCn', 6, address(_poolMock), address(_usdcMock));
    _poolMock.init(_aTokenMock);

    _usdcToken = IERC20(address(_usdcMock));
    _maiToken = IERC20(address(_maiMock));
    _aToken = IERC20(address(_aTokenMock));

    _usdcMock.mint(_owner, 100_000_000 * 10 ** 6);
    _usdcMock.mint(_user, 100_000_000 * 10 ** 6);

    _psm = new AaveUSDPSMV1();
    _maiMock.mint(address(_psm), 100_000_000 * 10 ** 18);
    _psm.initialize(address(_aTokenMock), 100, 100, address(_maiMock));

    vm.stopPrank();
  }
}
