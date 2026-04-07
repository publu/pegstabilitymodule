// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Script.sol';
import '../interfaces/IFly.sol';
import '../interfaces/IERC20.sol';

library MorphoVaultPSMPreflight {
  error GemAddressIsZero();
  error GemHasNoCode();
  error GemAssetCallFailed();
  error UnderlyingHasNoCode();
  error GemDecimalsCallFailed();
  error UnderlyingDecimalsCallFailed();
  error InvalidDepositFee(uint256 fee);
  error InvalidWithdrawalFee(uint256 fee);
  error DecimalDifferenceOverflow();
  error DepositFunctionNotSupported();
  error WithdrawFunctionNotSupported();
  error MAIAddressIsZero();
  error MAIHasNoCode();

  uint256 private constant MAX_FEE_BPS = 10_000; // 100%

  /// @notice Validates initialization parameters for MorphoVaultPSM
  /// @param gem The address of the IFly vault
  /// @param depositFee The deposit fee in basis points
  /// @param withdrawalFee The withdrawal fee in basis points
  /// @param maiAddress The address of the MAI token
  function validateInitParams(address gem, uint256 depositFee, uint256 withdrawalFee, address maiAddress) internal view {
    console.log('Starting preflight checks for MorphoVaultPSM initialization...');

    // Validate gem address
    console.log('Checking gem address: %s', gem);
    if (gem == address(0)) revert GemAddressIsZero();

    if (!_hasCode(gem)) revert GemHasNoCode();
    console.log('  [OK] Gem address has contract code');

    // Validate IFly interface - try to get asset
    address underlying = _tryGetAsset(gem);
    console.log('  [OK] Gem implements IFly.asset()');
    console.log('  Underlying asset: %s', underlying);

    // Validate underlying token
    if (!_hasCode(underlying)) revert UnderlyingHasNoCode();
    console.log('  [OK] Underlying asset has contract code');

    // Validate decimals calls
    uint8 gemDecimals = _tryGetGemDecimals(gem);
    console.log('  [OK] Gem decimals: %d', gemDecimals);

    uint8 underlyingDecimals = _tryGetUnderlyingDecimals(underlying);
    console.log('  [OK] Underlying decimals: %d', underlyingDecimals);

    // Validate decimal difference calculation
    if (gemDecimals < underlyingDecimals) {
      revert DecimalDifferenceOverflow();
    }
    uint256 decimalDifference = uint256(gemDecimals - underlyingDecimals);
    console.log('  [OK] Decimal difference: %d', decimalDifference);

    // Validate fee parameters
    console.log('Checking fee parameters...');
    if (depositFee > MAX_FEE_BPS) {
      revert InvalidDepositFee(depositFee);
    }
    console.log('  [OK] Deposit fee valid: %d bps (%d%%)', depositFee, (depositFee * 100) / MAX_FEE_BPS);

    if (withdrawalFee > MAX_FEE_BPS) {
      revert InvalidWithdrawalFee(withdrawalFee);
    }
    console.log('  [OK] Withdrawal fee valid: %d bps (%d%%)', withdrawalFee, (withdrawalFee * 100) / MAX_FEE_BPS);

    // Validate MAI address
    console.log('Checking MAI address: %s', maiAddress);
    if (maiAddress == address(0)) revert MAIAddressIsZero();

    if (!_hasCode(maiAddress)) revert MAIHasNoCode();
    console.log('  [OK] MAI address has contract code');

    console.log('All preflight checks passed!');
  }

  /// @notice Checks if an address has contract code
  /// @param addr The address to check
  /// @return hasCode True if the address has code, false otherwise
  function _hasCode(
    address addr
  ) private view returns (bool hasCode) {
    uint256 size;
    assembly {
      size := extcodesize(addr)
    }
    hasCode = size > 0;
  }

  /// @notice Attempts to get the underlying asset from the gem vault
  /// @param gem The IFly vault address
  /// @return underlying The underlying asset address
  function _tryGetAsset(
    address gem
  ) private view returns (address underlying) {
    try IFly(gem).asset() returns (address _underlying) {
      underlying = _underlying;
    } catch {
      revert GemAssetCallFailed();
    }
  }

  /// @notice Attempts to get the decimals from the gem vault
  /// @param gem The IFly vault address
  /// @return decimals The number of decimals
  function _tryGetGemDecimals(
    address gem
  ) private view returns (uint8 decimals) {
    try IFly(gem).decimals() returns (uint8 _decimals) {
      decimals = _decimals;
    } catch {
      revert GemDecimalsCallFailed();
    }
  }

  /// @notice Attempts to get the decimals from the underlying token
  /// @param underlying The underlying token address
  /// @return decimals The number of decimals
  function _tryGetUnderlyingDecimals(
    address underlying
  ) private view returns (uint8 decimals) {
    try IERC20(underlying).decimals() returns (uint8 _decimals) {
      decimals = _decimals;
    } catch {
      revert UnderlyingDecimalsCallFailed();
    }
  }
}
