// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {MockERC20 as ForgeMockERC20} from 'forge-std/mocks/MockERC20.sol';

/// @title MockERC20
/// @notice Test-only ERC20 mock. Wraps forge-std's `MockERC20` so that it exposes
///         a normal constructor (rather than an initializer) and public `mint`/`burn`
///         helpers for tests to seed balances without fork-based `deal()`.
/// @dev DO NOT use in production. Intended for use inside `solidity/test/` only.
contract MockERC20 is ForgeMockERC20 {
  constructor(
    string memory _name,
    string memory _symbol,
    uint8 _decimals
  ) {
    initialize(_name, _symbol, _decimals);
  }

  /// @notice Mint `_amount` tokens to `_to`. Unrestricted — this is a test mock.
  function mint(
    address _to,
    uint256 _amount
  ) external {
    _mint(_to, _amount);
  }

  /// @notice Burn `_amount` tokens from `_from`. Unrestricted — this is a test mock.
  function burn(
    address _from,
    uint256 _amount
  ) external {
    _burn(_from, _amount);
  }
}
