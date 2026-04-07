// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from 'interfaces/IERC20.sol';

/// @title USDCVaultPSM
/// @notice One-way Peg Stability Module: users deposit USDC and receive MAI (no reverse direction)
contract USDCVaultPSM {
  address public MAI_ADDRESS;
  address public USDC_ADDRESS;

  uint256 public totalDeposited;
  uint256 public depositFee;
  uint256 public minimumDepositFee;
  uint256 public maxDeposit;
  uint256 public upgradeTime;

  address public owner;
  address public pendingOwner;

  mapping(bytes4 => bool) public paused;
  bool public stopped;
  bool public initialized;

  error CallerIsNotOwner();
  error ContractIsPaused();
  error InvalidAmount();
  error InsufficientMAIBalance();
  error AlreadyInitialized();
  error NewOwnerCannotBeZeroAddress();
  error CallerIsNotPendingOwner();
  error UpgradeNotScheduled();
  error MAIAddressCannotBeZero();
  error USDCAddressCannotBeZero();

  event Deposited(address indexed _user, uint256 _amount);
  event OwnerUpdated(address _newOwner);
  event OwnershipTransferStarted(address indexed _previousOwner, address indexed _newOwner);
  event FeesWithdrawn(address indexed _owner, uint256 _feesEarned);
  event PauseEvent(address _account, bytes4 _selector, bool _paused);
  event MaxDepositUpdated(uint256 _maxDeposit);
  event MinimumFeeUpdated(uint256 _newMinimumDepositFee);
  event FeeUpdated(uint256 _newDepositFee);

  constructor() {
    owner = msg.sender;
  }

  modifier onlyOwner() {
    if (msg.sender != owner) revert CallerIsNotOwner();
    _;
  }

  modifier pausable() {
    if (paused[msg.sig] || stopped && block.timestamp > upgradeTime) revert ContractIsPaused();
    _;
  }

  function initialize(
    uint256 _depositFee,
    address _maiAddress,
    address _usdcAddress
  ) external onlyOwner {
    if (initialized) revert AlreadyInitialized();
    if (_maiAddress == address(0)) revert MAIAddressCannotBeZero();
    if (_usdcAddress == address(0)) revert USDCAddressCannotBeZero();

    depositFee = _depositFee;
    minimumDepositFee = 0;
    maxDeposit = 1e12; // 1 million USDC (6 decimals)
    MAI_ADDRESS = _maiAddress;
    USDC_ADDRESS = _usdcAddress;
    initialized = true;
  }

  /// @notice User deposits USDC and receives MAI at 1:1 (minus fee)
  /// @param _amount The amount of USDC to deposit (6 decimals)
  function deposit(
    uint256 _amount
  ) external pausable {
    if (_amount <= minimumDepositFee || _amount > maxDeposit) revert InvalidAmount();

    IERC20(USDC_ADDRESS).transferFrom(msg.sender, address(this), _amount);
    uint256 _fee = calculateFee(_amount);
    uint256 _netAmount = _amount - _fee;
    totalDeposited += _netAmount;

    uint256 _maiAmount = _netAmount * 1e12; // Convert from USDC (6) to MAI (18) decimals
    if (IERC20(MAI_ADDRESS).balanceOf(address(this)) < _maiAmount) {
      revert InsufficientMAIBalance();
    }
    IERC20(MAI_ADDRESS).transfer(msg.sender, _maiAmount);
    emit Deposited(msg.sender, _netAmount);
  }

  /// @notice Calculates the deposit fee
  /// @param _amount The amount to calculate the fee on (6 decimals)
  /// @return _fee The calculated fee
  function calculateFee(
    uint256 _amount
  ) public view returns (uint256 _fee) {
    _fee = _amount * depositFee / 10_000;
    _fee = _fee < minimumDepositFee ? minimumDepositFee : _fee;
  }

  /// @notice Allows the owner to claim accumulated USDC fees
  function claimFees() external onlyOwner {
    uint256 balance = IERC20(USDC_ADDRESS).balanceOf(address(this));
    if (balance > totalDeposited) {
      uint256 _fees = balance - totalDeposited;
      IERC20(USDC_ADDRESS).transfer(msg.sender, _fees);
      emit FeesWithdrawn(msg.sender, _fees);
    }
  }

  function setPaused(
    bytes4 _selector,
    bool _paused
  ) external onlyOwner {
    paused[_selector] = _paused;
    emit PauseEvent(msg.sender, _selector, _paused);
  }

  function transferOwnership(
    address _newOwner
  ) external onlyOwner {
    if (_newOwner == address(0)) revert NewOwnerCannotBeZeroAddress();
    pendingOwner = _newOwner;
    emit OwnershipTransferStarted(owner, _newOwner);
  }

  function acceptOwnership() external {
    if (msg.sender != pendingOwner) revert CallerIsNotPendingOwner();
    emit OwnerUpdated(msg.sender);
    owner = msg.sender;
    pendingOwner = address(0);
  }

  function cancelUpgrade() external onlyOwner {
    stopped = false;
    upgradeTime = 0;
  }

  function setUpgrade() external onlyOwner {
    if (!stopped) {
      stopped = true;
      upgradeTime = block.timestamp + 2 days;
    }
  }

  function transferToken(
    address _token,
    address _to,
    uint256 _amount
  ) external onlyOwner {
    if (_token != USDC_ADDRESS || (stopped && block.timestamp > upgradeTime)) {
      IERC20(_token).transfer(_to, _amount);
    } else {
      revert UpgradeNotScheduled();
    }
  }

  /// @notice Allows the owner to withdraw MAI tokens from the contract
  function withdrawMAI() external onlyOwner {
    IERC20 _mai = IERC20(MAI_ADDRESS);
    _mai.transfer(msg.sender, _mai.balanceOf(address(this)));
  }

  function updateMinimumFee(
    uint256 _newMinimumDepositFee
  ) external onlyOwner {
    minimumDepositFee = _newMinimumDepositFee;
    emit MinimumFeeUpdated(_newMinimumDepositFee);
  }

  function updateFeeBP(
    uint256 _newDepositFee
  ) external onlyOwner {
    depositFee = _newDepositFee;
    emit FeeUpdated(_newDepositFee);
  }

  function updateMaxDeposit(
    uint256 _maxDeposit
  ) external onlyOwner {
    maxDeposit = _maxDeposit;
    emit MaxDepositUpdated(_maxDeposit);
  }
}
