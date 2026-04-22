// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IAavePool} from '../../interfaces/IAavePool.sol';
import {MockERC20} from './MockERC20.sol';
import {MockAToken} from './MockAToken.sol';

/// @title MockAavePool
/// @notice Test-only mock of Aave V3's `IPool` surface that `AaveUSDPSM/V1`
///         actually uses: `supply`, `withdraw`, and `getReserveData`. Real
///         Aave aTokens are minted 1:1 with the supplied underlying and
///         rebased via `liquidityIndex`; this mock keeps it simple —
///         `aToken.balanceOf` reflects principal + simulated yield, and
///         underlying moves 1:1 in and out of the pool's own balance.
/// @dev DO NOT use in production.
contract MockAavePool is IAavePool {
  error AssetMismatch();
  error PoolNotInitialized();
  error AlreadyInitialized();
  error InsufficientBalance();

  event Supply(address indexed asset, address indexed from, address indexed onBehalfOf, uint256 amount);
  event Withdraw(address indexed asset, address indexed caller, address indexed to, uint256 amount);

  MockERC20 internal immutable _underlying;
  MockAToken internal _aToken;
  bool public revertOnWithdraw;

  constructor(
    MockERC20 underlying_
  ) {
    _underlying = underlying_;
  }

  /// @notice One-shot setter. Needed because `MockAToken` stores the pool address
  ///         as an immutable, so the pool must exist before the aToken is deployed.
  function init(
    MockAToken aToken_
  ) external {
    if (address(_aToken) != address(0)) revert AlreadyInitialized();
    _aToken = aToken_;
  }

  function aToken() external view returns (address) {
    return address(_aToken);
  }

  function underlying() external view returns (address) {
    return address(_underlying);
  }

  /// @inheritdoc IAavePool
  function supply(
    address asset,
    uint256 amount,
    address onBehalfOf,
    uint16
  ) external override {
    if (address(_aToken) == address(0)) revert PoolNotInitialized();
    if (asset != address(_underlying)) revert AssetMismatch();

    _underlying.transferFrom(msg.sender, address(this), amount);
    _aToken.mint(onBehalfOf, amount);

    emit Supply(asset, msg.sender, onBehalfOf, amount);
  }

  /// @inheritdoc IAavePool
  /// @dev Passing `type(uint256).max` as `amount` drains the caller's full
  ///      aToken balance, matching the real Aave V3 behavior.
  function withdraw(
    address asset,
    uint256 amount,
    address to
  ) external override returns (uint256) {
    if (revertOnWithdraw) revert('MockAavePool: withdraw disabled');
    if (address(_aToken) == address(0)) revert PoolNotInitialized();
    if (asset != address(_underlying)) revert AssetMismatch();

    uint256 _balance = _aToken.balanceOf(msg.sender);
    if (amount == type(uint256).max) {
      amount = _balance;
    } else if (amount > _balance) {
      revert InsufficientBalance();
    }
    if (amount > _underlying.balanceOf(address(this))) revert InsufficientBalance();

    _aToken.burn(msg.sender, amount);
    _underlying.transfer(to, amount);

    emit Withdraw(asset, msg.sender, to, amount);
    return amount;
  }

  /// @inheritdoc IAavePool
  function getReserveData(
    address asset
  ) external view override returns (ReserveDataLegacy memory data) {
    if (asset == address(_underlying)) {
      data.aTokenAddress = address(_aToken);
    }
  }

  // --- Test-only knobs ---

  /// @notice Grow `holder`'s aToken balance without a supply, simulating
  ///         Aave's rebasing yield. Also mints underlying into the pool so
  ///         subsequent withdraws can succeed.
  function simulateYield(
    address holder,
    uint256 amount
  ) external {
    _aToken.mint(holder, amount);
    _underlying.mint(address(this), amount);
  }

  /// @notice Shrink `holder`'s aToken balance without a withdraw. Used by
  ///         tests to model bad-debt socialization or dust.
  function simulateLoss(
    address holder,
    uint256 amount
  ) external {
    _aToken.burn(holder, amount);
  }

  /// @notice Toggle `withdraw` to revert. Models the PSM observing an
  ///         Aave incident (pool paused, reserve frozen) during evacuation.
  function setRevertOnWithdraw(
    bool enabled
  ) external {
    revertOnWithdraw = enabled;
  }
}
