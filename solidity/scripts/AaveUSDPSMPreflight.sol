// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Script.sol';
import '../interfaces/IAavePool.sol';
import '../interfaces/IERC20.sol';

library AaveUSDPSMPreflight {
  error GemAddressIsZero();
  error GemHasNoCode();
  error ATokenPoolCallFailed();
  error ATokenUnderlyingCallFailed();
  error ATokenDecimalsCallFailed();
  error UnderlyingHasNoCode();
  error UnderlyingDecimalsCallFailed();
  error PoolHasNoCode();
  error PoolMismatch(address derivedFromAToken, address expected);
  error UnderlyingMismatch(address derivedFromAToken, address expected);
  error ReserveATokenMismatch(address reserveAToken, address gem);
  error DecimalsMismatch(uint8 aTokenDecimals, uint8 underlyingDecimals);
  error InvalidDepositFee(uint256 fee);
  error InvalidWithdrawalFee(uint256 fee);
  error MAIAddressIsZero();
  error MAIHasNoCode();
  error MAIDecimalsNotSupported(uint8 decimals);

  uint256 private constant MAX_FEE_BPS = 10_000; // 100%

  /// @notice Validates initialization parameters for AaveUSDPSM. Mirrors
  ///         `MorphoVaultPSMPreflight` but reads Aave-specific getters —
  ///         aToken.POOL(), aToken.UNDERLYING_ASSET_ADDRESS(), and the
  ///         pool's own aTokenAddress via getReserveData(underlying).
  function validateInitParams(
    address gem,
    address expectedPool,
    address expectedUnderlying,
    uint256 depositFee,
    uint256 withdrawalFee,
    address maiAddress
  ) internal view {
    console.log('Starting preflight checks for AaveUSDPSM initialization...');
    console.log('Checking gem (aToken) address: %s', gem);
    if (gem == address(0)) revert GemAddressIsZero();
    if (!_hasCode(gem)) revert GemHasNoCode();
    console.log('  [OK] aToken has contract code');

    // aToken.POOL()
    address derivedPool = _tryGetPool(gem);
    console.log('  [OK] aToken.POOL(): %s', derivedPool);
    if (expectedPool != address(0) && derivedPool != expectedPool) {
      revert PoolMismatch(derivedPool, expectedPool);
    }
    if (!_hasCode(derivedPool)) revert PoolHasNoCode();
    console.log('  [OK] Pool has contract code');

    // aToken.UNDERLYING_ASSET_ADDRESS()
    address derivedUnderlying = _tryGetUnderlying(gem);
    console.log('  [OK] aToken.UNDERLYING_ASSET_ADDRESS(): %s', derivedUnderlying);
    if (expectedUnderlying != address(0) && derivedUnderlying != expectedUnderlying) {
      revert UnderlyingMismatch(derivedUnderlying, expectedUnderlying);
    }
    if (!_hasCode(derivedUnderlying)) revert UnderlyingHasNoCode();
    console.log('  [OK] Underlying has contract code');

    // Cross-check: pool.getReserveData(underlying).aTokenAddress == gem
    address reserveAToken = _tryGetReserveAToken(derivedPool, derivedUnderlying);
    console.log('  [OK] pool.getReserveData(underlying).aTokenAddress: %s', reserveAToken);
    if (reserveAToken != gem) revert ReserveATokenMismatch(reserveAToken, gem);
    console.log('  [OK] Pool reserve wiring matches gem');

    // Decimals
    uint8 aTokenDecimals = _tryGetATokenDecimals(gem);
    uint8 underlyingDecimals = _tryGetUnderlyingDecimals(derivedUnderlying);
    console.log('  aToken decimals: %d', aTokenDecimals);
    console.log('  underlying decimals: %d', underlyingDecimals);
    if (aTokenDecimals != underlyingDecimals) revert DecimalsMismatch(aTokenDecimals, underlyingDecimals);

    // Fees
    console.log('Checking fee parameters...');
    if (depositFee > MAX_FEE_BPS) revert InvalidDepositFee(depositFee);
    console.log('  [OK] Deposit fee: %d bps', depositFee);
    if (withdrawalFee > MAX_FEE_BPS) revert InvalidWithdrawalFee(withdrawalFee);
    console.log('  [OK] Withdrawal fee: %d bps', withdrawalFee);

    // MAI
    console.log('Checking MAI address: %s', maiAddress);
    if (maiAddress == address(0)) revert MAIAddressIsZero();
    if (!_hasCode(maiAddress)) revert MAIHasNoCode();
    uint8 maiDecimals = _tryGetUnderlyingDecimals(maiAddress);
    console.log('  MAI decimals: %d', maiDecimals);
    if (maiDecimals <= underlyingDecimals) revert MAIDecimalsNotSupported(maiDecimals);

    console.log('All preflight checks passed!');
  }

  function _hasCode(
    address addr
  ) private view returns (bool hasCode) {
    uint256 size;
    assembly {
      size := extcodesize(addr)
    }
    hasCode = size > 0;
  }

  function _tryGetPool(
    address gem
  ) private view returns (address pool) {
    try IAToken(gem).POOL() returns (address _pool) {
      pool = _pool;
    } catch {
      revert ATokenPoolCallFailed();
    }
  }

  function _tryGetUnderlying(
    address gem
  ) private view returns (address underlying) {
    try IAToken(gem).UNDERLYING_ASSET_ADDRESS() returns (address _u) {
      underlying = _u;
    } catch {
      revert ATokenUnderlyingCallFailed();
    }
  }

  function _tryGetReserveAToken(
    address pool,
    address underlying
  ) private view returns (address aToken) {
    try IAavePool(pool).getReserveData(underlying) returns (IAavePool.ReserveDataLegacy memory data) {
      aToken = data.aTokenAddress;
    } catch {
      aToken = address(0);
    }
  }

  function _tryGetATokenDecimals(
    address gem
  ) private view returns (uint8 decimals) {
    try IAToken(gem).decimals() returns (uint8 _d) {
      decimals = _d;
    } catch {
      revert ATokenDecimalsCallFailed();
    }
  }

  function _tryGetUnderlyingDecimals(
    address underlying
  ) private view returns (uint8 decimals) {
    try IERC20(underlying).decimals() returns (uint8 _d) {
      decimals = _d;
    } catch {
      revert UnderlyingDecimalsCallFailed();
    }
  }
}
