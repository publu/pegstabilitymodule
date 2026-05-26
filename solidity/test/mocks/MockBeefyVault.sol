// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {MockERC20} from './MockERC20.sol';

/// @title MockBeefyVault
/// @notice Test-only mock of the Beefy `IBeefy` interface. Implements the subset that
///         `BeefyVaultPSM/V1`, `BeefyVaultPSM/V2`, and `BeefyVaultPSMPoly/V1` actually
///         call: `balance`, `balanceOf`, `decimals`, `depositAll`, `totalSupply`,
///         `want`, `withdraw`, `withdrawAll`, plus the ERC20 share surface.
/// @dev The mock holds real underlying token balances via `MockERC20.transferFrom`,
///      so tests exercise the full deposit/withdraw callpath. Share accounting is
///      tracked internally. `getPricePerFullShare` returns `_initialPricePerShare`
///      when no shares are minted and the live ratio once the vault has state.
///      DO NOT use in production.
contract MockBeefyVault {
  error InsufficientShares();
  error InsufficientAllowance();
  error DepositAllReverted();

  event Transfer(address indexed from, address indexed to, uint256 amount);
  event Approval(address indexed owner, address indexed spender, uint256 amount);

  MockERC20 internal immutable _want;
  uint8 internal immutable _decimalsInternal;
  uint256 internal _initialPricePerShare;

  uint256 public totalSupply;
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;
  bool public revertOnDepositAll;

  /// @param want_ The underlying ERC20 token the vault wraps.
  /// @param decimals_ The vault-share decimals. Typically 18 (matches real Beefy mooTokens).
  /// @param initialPricePerShare_ The 1e18-denominated assets-per-share ratio used before
  ///        any deposit exists. Pass `1e18` for a clean 1:1 setup, or a non-trivial value
  ///        like `1.05e18` to stress share-price math. No default — every call site picks.
  constructor(
    MockERC20 want_,
    uint8 decimals_,
    uint256 initialPricePerShare_
  ) {
    _want = want_;
    _decimalsInternal = decimals_;
    _initialPricePerShare = initialPricePerShare_;
  }

  // --- IBeefy surface actually called by PSM contracts ---

  function want() external view returns (address) {
    return address(_want);
  }

  function decimals() external view returns (uint8) {
    return _decimalsInternal;
  }

  function balance() external view returns (uint256) {
    return _want.balanceOf(address(this));
  }

  function getPricePerFullShare() external view returns (uint256) {
    if (totalSupply == 0) return _initialPricePerShare;
    return (_want.balanceOf(address(this)) * 1e18) / totalSupply;
  }

  /// @notice Pull the caller's entire `want` balance and mint proportional shares.
  ///         Matches Beefy's `depositAll` semantics.
  function depositAll() external {
    if (revertOnDepositAll) revert DepositAllReverted();
    _deposit(_want.balanceOf(msg.sender));
  }

  /// @notice Pull `_amount` underlying from the caller and mint proportional shares.
  ///         Matches Beefy's `deposit(uint256)` semantics — not called by the
  ///         production PSM contracts (they use `depositAll`), but test code that
  ///         drives the vault directly (e.g., `test_ClaimFees` in `BeefyVaultW.sol`)
  ///         uses this entry point.
  function deposit(
    uint256 _amount
  ) external {
    _deposit(_amount);
  }

  function _deposit(
    uint256 _amount
  ) internal {
    uint256 _liveBalance = _want.balanceOf(address(this));
    _want.transferFrom(msg.sender, address(this), _amount);

    uint256 _shares;
    if (totalSupply == 0) {
      // First deposit: scale by initial price per share to preserve ratio.
      _shares = (_amount * 1e18) / _initialPricePerShare;
    } else {
      _shares = (_amount * totalSupply) / _liveBalance;
    }
    _mint(msg.sender, _shares);
  }

  /// @notice Burn `_shares` from the caller and return proportional underlying.
  function withdraw(
    uint256 _shares
  ) external {
    if (_shares > balanceOf[msg.sender]) revert InsufficientShares();
    uint256 _amountOut = (_shares * _want.balanceOf(address(this))) / totalSupply;
    _burn(msg.sender, _shares);
    _want.transfer(msg.sender, _amountOut);
  }

  /// @notice Burn all of the caller's shares and return proportional underlying.
  function withdrawAll() external {
    uint256 _shares = balanceOf[msg.sender];
    if (_shares == 0) revert InsufficientShares();
    uint256 _amountOut = (_shares * _want.balanceOf(address(this))) / totalSupply;
    _burn(msg.sender, _shares);
    _want.transfer(msg.sender, _amountOut);
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

  function setRevertOnDepositAll(
    bool enabled
  ) external {
    revertOnDepositAll = enabled;
  }

  /// @notice Grow the vault's underlying balance without minting shares, raising
  ///         `getPricePerFullShare`. Used by tests to model yield accrual.
  function simulateYield(
    uint256 _amount
  ) external {
    _want.mint(address(this), _amount);
  }

  /// @notice Shrink the vault's underlying balance without burning shares, lowering
  ///         `getPricePerFullShare`. Used by tests to model loss.
  function simulateLoss(
    uint256 _amount
  ) external {
    _want.burn(address(this), _amount);
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
