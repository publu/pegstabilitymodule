// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {MockERC20} from './MockERC20.sol';

/// @title MockAToken
/// @notice Test-only mock of an Aave V3 aToken. Extends `MockERC20` with the two
///         getters `AaveUSDPSM/V1` reads at init time: `POOL()` and
///         `UNDERLYING_ASSET_ADDRESS()`. `balanceOf` semantics stay inherited
///         from `MockERC20` — rebasing is simulated by the companion
///         `MockAavePool` via direct `mint`/`burn`.
/// @dev DO NOT use in production.
contract MockAToken is MockERC20 {
  address public immutable POOL;
  address public immutable UNDERLYING_ASSET_ADDRESS;

  constructor(
    string memory _name,
    string memory _symbol,
    uint8 _decimals,
    address _pool,
    address _underlying
  ) MockERC20(_name, _symbol, _decimals) {
    POOL = _pool;
    UNDERLYING_ASSET_ADDRESS = _underlying;
  }
}
