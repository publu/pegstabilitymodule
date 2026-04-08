// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {MockERC20} from './MockERC20.sol';

/// @title MockERC4626Vault
/// @notice Test-only mock of the `IL2DSR` / `IFly` ERC4626-style vault interface.
///         Implements only the subset that `DAIVaultPSM/V1` actually calls:
///         `asset`, `balanceOf`, `convertToAssets`, `deposit(assets, receiver)`,
///         and `withdraw(assets, receiver, owner)`, plus the ERC20 share surface.
/// @dev Matches the signature shape of both `IL2DSR` and `IFly` so it can satisfy
///      either. The unused ERC4626 methods (`convertToShares`, `redeem`, `mint`,
///      `previewXxx`, `maxXxx`, `totalAssets`) are intentionally omitted — adding
///      them without a test consumer is dead surface.
///      The mock holds real asset balances via `MockERC20.transferFrom`, so tests
///      exercise the full deposit/withdraw callpath. DO NOT use in production.
contract MockERC4626Vault {
  error InsufficientShares();
  error InsufficientAllowance();
  error ZeroShares();

  event Transfer(address indexed from, address indexed to, uint256 amount);
  event Approval(address indexed owner, address indexed spender, uint256 amount);
  event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
  event Withdraw(
    address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
  );

  MockERC20 internal immutable _assetToken;
  uint8 internal immutable _decimalsInternal;
  uint256 internal _initialSharePrice;

  uint256 public totalSupply;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  /// @param asset_ The underlying ERC20 that the vault wraps.
  /// @param decimals_ Share decimals. Typically matches `asset_.decimals()`.
  /// @param initialSharePrice_ 1e18-denominated assets-per-share ratio used before any
  ///        deposit exists. Pass `1e18` for 1:1, or a non-trivial value to stress math.
  ///        No default — every call site picks deliberately.
  constructor(
    MockERC20 asset_,
    uint8 decimals_,
    uint256 initialSharePrice_
  ) {
    _assetToken = asset_;
    _decimalsInternal = decimals_;
    _initialSharePrice = initialSharePrice_;
  }

  // --- IL2DSR / IFly surface actually called by PSM contracts ---

  function asset() external view returns (address) {
    return address(_assetToken);
  }

  function decimals() external view returns (uint8) {
    return _decimalsInternal;
  }

  function convertToAssets(
    uint256 _shares
  ) public view returns (uint256) {
    if (totalSupply == 0) return (_shares * _initialSharePrice) / 1e18;
    return (_shares * _assetToken.balanceOf(address(this))) / totalSupply;
  }

  /// @notice Deposit `_assets` underlying, mint proportional shares to `_receiver`.
  function deposit(
    uint256 _assets,
    address _receiver
  ) external returns (uint256 _shares) {
    uint256 _liveAssets = _assetToken.balanceOf(address(this));
    _assetToken.transferFrom(msg.sender, address(this), _assets);

    if (totalSupply == 0) {
      _shares = (_assets * 1e18) / _initialSharePrice;
    } else {
      _shares = (_assets * totalSupply) / _liveAssets;
    }
    if (_shares == 0) revert ZeroShares();
    _mint(_receiver, _shares);
    emit Deposit(msg.sender, _receiver, _assets, _shares);
  }

  /// @notice Burn shares from `_owner` to return `_assets` underlying to `_receiver`.
  ///         Burns are rounded up to ensure the vault does not give out more assets
  ///         than the caller is paying in shares (OZ ERC4626 convention).
  function withdraw(
    uint256 _assets,
    address _receiver,
    address _owner
  ) external returns (uint256 _shares) {
    uint256 _liveAssets = _assetToken.balanceOf(address(this));
    if (totalSupply == 0 || _liveAssets == 0) revert InsufficientShares();

    _shares = (_assets * totalSupply) / _liveAssets;
    // Round up to protect the vault from dust drains
    if ((_shares * _liveAssets) / totalSupply < _assets) _shares += 1;
    if (_shares == 0) revert ZeroShares();

    if (msg.sender != _owner) {
      uint256 _allowed = allowance[_owner][msg.sender];
      if (_allowed != type(uint256).max) {
        if (_allowed < _shares) revert InsufficientAllowance();
        allowance[_owner][msg.sender] = _allowed - _shares;
      }
    }
    if (_shares > balanceOf[_owner]) revert InsufficientShares();
    _burn(_owner, _shares);
    _assetToken.transfer(_receiver, _assets);
    emit Withdraw(msg.sender, _receiver, _owner, _assets, _shares);
  }

  // --- ERC20 share surface ---

  function approve(
    address _spender,
    uint256 _amount
  ) external returns (bool) {
    allowance[msg.sender][_spender] = _amount;
    emit Approval(msg.sender, _spender, _amount);
    return true;
  }

  function transfer(
    address _to,
    uint256 _amount
  ) external returns (bool) {
    _transfer(msg.sender, _to, _amount);
    return true;
  }

  function transferFrom(
    address _from,
    address _to,
    uint256 _amount
  ) external returns (bool) {
    uint256 _allowed = allowance[_from][msg.sender];
    if (_allowed != type(uint256).max) {
      if (_allowed < _amount) revert InsufficientAllowance();
      allowance[_from][msg.sender] = _allowed - _amount;
    }
    _transfer(_from, _to, _amount);
    return true;
  }

  // --- Test-only knobs ---

  /// @notice Grow the vault's underlying balance without minting shares, raising the
  ///         assets-per-share ratio. Used by tests to model yield accrual.
  function simulateYield(
    uint256 _amount
  ) external {
    _assetToken.mint(address(this), _amount);
  }

  // --- Internal ---

  function _mint(
    address _to,
    uint256 _amount
  ) internal {
    totalSupply += _amount;
    balanceOf[_to] += _amount;
    emit Transfer(address(0), _to, _amount);
  }

  function _burn(
    address _from,
    uint256 _amount
  ) internal {
    balanceOf[_from] -= _amount;
    totalSupply -= _amount;
    emit Transfer(_from, address(0), _amount);
  }

  function _transfer(
    address _from,
    address _to,
    uint256 _amount
  ) internal {
    balanceOf[_from] -= _amount;
    balanceOf[_to] += _amount;
    emit Transfer(_from, _to, _amount);
  }
}
