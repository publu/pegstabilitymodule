// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IFly} from '../interfaces/IFly.sol';
import {IERC20} from '../interfaces/IERC20.sol';

contract MorphoVaultPSM {
  uint256 public constant MAX_INT =
    115_792_089_237_316_195_423_570_985_008_687_907_853_269_984_665_640_564_039_457_584_007_913_129_639_935;
  address public MAI_ADDRESS;

  uint256 public totalStableLiquidity;
  uint256 public totalQueuedLiquidity;
  uint256 public depositFee;
  uint256 public withdrawalFee;
  uint256 public minimumDepositFee;
  uint256 public minimumWithdrawalFee;

  uint256 public maxDeposit;
  uint256 public maxWithdraw;
  uint256 public upgradeTime;
  uint256 public decimalDifference;

  address public underlying;
  address public owner;
  address public gem;

  mapping(address => uint256) public withdrawalEpoch;
  mapping(address => uint256) public scheduledWithdrawalAmount;

  mapping(bytes4 => bool) public paused;
  bool public stopped;

  bool public initialized;

  bool public evacuated;
  mapping(address => bool) public guardians;
  uint256 public totalQueuedMAI;

  error CallerIsNotOwner();
  error ContractIsPaused();
  error InvalidAmount();
  error InvalidAmountAfterFee();
  error InsufficientMAIBalance();
  error WithdrawalAlreadyScheduled();
  error NotWithinWithdrawalPeriod();
  error NoWithdrawalScheduled();
  error WithdrawalAlreadyExecutable();
  error AlreadyInitialized();
  error NewOwnerCannotBeZeroAddress();
  error WithdrawalNotAvailable();
  error NotEnoughLiquidity();
  error UpgradeNotScheduled();
  error MAIAddressCannotBeZero();
  error NotEvacuated();
  error CallerIsNotGuardianOrOwner();
  error GuardianCannotBeZeroAddress();

  // Events
  event Deposited(address indexed _user, uint256 _amount);
  event Withdrawn(address indexed _user, uint256 _amount);
  event OwnerUpdated(address _newOwner);
  event MAIRemoved(address indexed _user, uint256 _amount);
  event FeesWithdrawn(address indexed _owner, uint256 _feesEarned);
  event PauseEvent(address _account, bytes4 _selector, bool _paused);
  event WithdrawalCancelled(address indexed _user, uint256 _amount);
  event ScheduledWithdrawal(address indexed _user, uint256 _amount);
  event WithdrawalScheduled(address indexed _user, uint256 _amount);
  event MaxDepositUpdated(uint256 _maxDeposit);
  event MaxWithdrawUpdated(uint256 _maxWithdraw);
  event MinimumFeesUpdated(uint256 _newMinimumDepositFee, uint256 _newMinimumWithdrawalFee);
  event FeesUpdated(uint256 _newDepositFee, uint256 _newWithdrawalFee);
  event MaxUpdated(uint256 _maxDeposit, uint256 _maxWithdraw);
  event VaultEvacuated(address indexed _caller, uint256 _sharesRedeemed);
  event Swept(address indexed _caller, uint256 _amount);
  event RefundClaimed(address indexed _user, uint256 _maiAmount);
  event GuardianUpdated(address _guardian, bool _enabled);
  event RedeemFailed(bytes _reason);

  constructor() {
    owner = msg.sender;
  }

  modifier onlyOwner() {
    if (msg.sender != owner) revert CallerIsNotOwner();
    _;
  }

  modifier onlyGuardianOrOwner() {
    if (msg.sender != owner && !guardians[msg.sender]) revert CallerIsNotGuardianOrOwner();
    _;
  }

  modifier pausable() {
    if (paused[msg.sig] || evacuated || (stopped && block.timestamp > upgradeTime)) revert ContractIsPaused();
    _;
  }

  function initialize(
    address _gem,
    uint256 _depositFee,
    uint256 _withdrawalFee,
    address _maiAddress
  ) external onlyOwner {
    if (initialized) {
      revert AlreadyInitialized();
    }
    if (_maiAddress == address(0)) {
      revert MAIAddressCannotBeZero();
    }
    depositFee = _depositFee;
    withdrawalFee = _withdrawalFee;
    minimumDepositFee = 0;
    minimumWithdrawalFee = 1_000_000; // 1 dollar

    IFly _beef = IFly(_gem);

    maxDeposit = 1e24; // 1 million ether
    maxWithdraw = 1e24; // 1 million ether
    underlying = _beef.asset();
    decimalDifference = uint256(_beef.decimals() - IERC20(underlying).decimals());
    gem = _gem;
    MAI_ADDRESS = _maiAddress;
    initialized = true;
    approveGem();
  }

  function approveGem() public {
    IERC20(underlying).approve(gem, MAX_INT);
  }

  /// @notice User deposits tokens with 18 decimals and withdraws stablecoin
  /// @param _amount The amount of tokens to deposit
  function deposit(
    uint256 _amount
  ) external pausable {
    if (_amount <= minimumDepositFee || _amount > maxDeposit) revert InvalidAmount();
    IERC20 iunder = IERC20(underlying);
    iunder.transferFrom(msg.sender, address(this), _amount);
    uint256 _fee = calculateFee(_amount, true);

    IFly(gem).deposit(iunder.balanceOf(address(this)), address(this));

    _amount = _amount - _fee;
    totalStableLiquidity += _amount;

    uint256 scaledAmount = _amount * (10 ** decimalDifference);
    if (IERC20(MAI_ADDRESS).balanceOf(address(this)) < scaledAmount) {
      revert InsufficientMAIBalance();
    }
    IERC20(MAI_ADDRESS).transfer(msg.sender, scaledAmount);
    emit Deposited(msg.sender, _amount);
  }

  /// @notice Schedules a withdrawal of stablecoin
  /// @param _amount The amount of stablecoin to withdraw
  function scheduleWithdraw(
    uint256 _amount
  ) external pausable {
    if (withdrawalEpoch[msg.sender] != 0) {
      revert WithdrawalAlreadyScheduled();
    }

    if (_amount < minimumWithdrawalFee || _amount > maxWithdraw) revert InvalidAmount();

    uint256 _toWithdraw = _amount / (10 ** decimalDifference);
    uint256 _fee = calculateFee(_toWithdraw, false);
    if (_toWithdraw <= _fee) revert InvalidAmountAfterFee();
    if ((totalStableLiquidity - totalQueuedLiquidity) < _toWithdraw) revert NotEnoughLiquidity();
    totalQueuedLiquidity += _toWithdraw;
    totalQueuedMAI += _amount;
    scheduledWithdrawalAmount[msg.sender] = _amount;
    IERC20(MAI_ADDRESS).transferFrom(msg.sender, address(this), _amount);
    withdrawalEpoch[msg.sender] = block.timestamp + 3 days;
    emit WithdrawalScheduled(msg.sender, _amount);
  }

  /// @notice Withdraws scheduled stablecoin after the withdrawal epoch
  function withdraw() external pausable {
    if (withdrawalEpoch[msg.sender] == 0 || block.timestamp < withdrawalEpoch[msg.sender]) {
      revert WithdrawalNotAvailable();
    }

    withdrawalEpoch[msg.sender] = 0;
    uint256 _amount = scheduledWithdrawalAmount[msg.sender];
    scheduledWithdrawalAmount[msg.sender] = 0;
    uint256 _toWithdraw = _amount / (10 ** decimalDifference);
    uint256 _fee = calculateFee(_toWithdraw, false);
    uint256 _toWithdrawwFee = (_toWithdraw - _fee);
    if (_toWithdraw > totalStableLiquidity) {
      revert NotEnoughLiquidity();
    }
    IFly vault = IFly(gem);

    totalStableLiquidity -= _toWithdraw;
    totalQueuedLiquidity -= _toWithdraw;
    totalQueuedMAI -= _amount;

    // This would withdraw and transfer to user
    vault.withdraw(_toWithdrawwFee, msg.sender, address(this));
    uint256 _remaining = IERC20(underlying).balanceOf(address(this));
    if (_remaining > 0) {
      vault.deposit(_remaining, address(this));
    }

    emit Withdrawn(msg.sender, _amount);
  }

  /// @notice Calculates the fee for deposit or withdrawal
  /// @param _amount The amount to calculate the fee on
  /// @param _deposit Boolean indicating if the fee is for a deposit (true) or withdrawal (false)
  /// @return _fee The calculated fee
  function calculateFee(
    uint256 _amount,
    bool _deposit
  ) public view returns (uint256 _fee) {
    if (_deposit) {
      _fee = _amount * depositFee / 10_000;
      _fee = _fee < minimumDepositFee ? minimumDepositFee : _fee;
    } else {
      _fee = _amount * withdrawalFee / 10_000;
      _fee = _fee < minimumWithdrawalFee ? minimumWithdrawalFee : _fee;
    }
  }

  /// @notice Allows the owner to claim fees accumulated in the contract
  function claimFees() external onlyOwner {
    IFly _beef = IFly(gem);

    uint256 totalShares = _beef.balanceOf(address(this));
    uint256 _totalStoredInUsd = _beef.convertToAssets(totalShares);
    if (_totalStoredInUsd > totalStableLiquidity) {
      uint256 _fees = (_totalStoredInUsd - totalStableLiquidity); // in USDC
      _beef.withdraw(_totalStoredInUsd - totalStableLiquidity, msg.sender, address(this));
      emit FeesWithdrawn(msg.sender, _fees);
      // directly sends the owner the amount
    }
  }

  /// @notice Emergency evacuation: withdraws all assets from the Morpho vault and freezes the contract
  function evacuateVault() external onlyGuardianOrOwner {
    evacuated = true;

    if (!stopped) {
      stopped = true;
      upgradeTime = block.timestamp + 2 days;
    }

    IFly vault = IFly(gem);
    uint256 totalShares = vault.balanceOf(address(this));
    if (totalShares > 0) {
      try vault.redeem(totalShares, address(this), address(this)) {}
      catch (bytes memory reason) {
        emit RedeemFailed(reason);
      }
    }

    emit VaultEvacuated(msg.sender, totalShares);
  }

  /// @notice Allows users with pending scheduled withdrawals to recover their MAI after evacuation
  function claimRefund() external {
    if (!evacuated) revert NotEvacuated();
    uint256 amount = scheduledWithdrawalAmount[msg.sender];
    if (amount == 0) revert NoWithdrawalScheduled();

    uint256 toRefund = amount / (10 ** decimalDifference);

    scheduledWithdrawalAmount[msg.sender] = 0;
    withdrawalEpoch[msg.sender] = 0;
    totalQueuedLiquidity -= toRefund;
    totalStableLiquidity -= toRefund;
    totalQueuedMAI -= amount;

    IERC20(MAI_ADDRESS).transfer(msg.sender, amount);
    emit RefundClaimed(msg.sender, amount);
  }

  /// @notice Deposits idle USDC in the contract into the Morpho vault with correct bookkeeping
  function sweep() external onlyOwner {
    if (evacuated) revert ContractIsPaused();

    IERC20 iunder = IERC20(underlying);
    uint256 balance = iunder.balanceOf(address(this));
    if (balance == 0) revert InvalidAmount();

    IFly(gem).deposit(balance, address(this));
    totalStableLiquidity += balance;

    emit Swept(msg.sender, balance);
  }

  /// @notice Adds or removes a guardian address for emergency evacuation
  /// @param _guardian The guardian address to add or remove
  /// @param _enabled True to add, false to remove
  function setGuardian(
    address _guardian,
    bool _enabled
  ) external onlyOwner {
    if (_enabled && _guardian == address(0)) revert GuardianCannotBeZeroAddress();
    guardians[_guardian] = _enabled;
    emit GuardianUpdated(_guardian, _enabled);
  }

  /// @notice Sets a function selector to paused or unpaused
  /// @param _selector The function selector to pause or unpause
  /// @param _paused Boolean indicating if the function should be paused (true) or unpaused (false)
  function setPaused(
    bytes4 _selector,
    bool _paused
  ) external onlyOwner {
    paused[_selector] = _paused;
    emit PauseEvent(msg.sender, _selector, _paused);
  }

  /// @notice Transfers ownership of the contract to a new owner
  /// @param _newOwner The address of the new owner
  function transferOwnership(
    address _newOwner
  ) external onlyOwner {
    if (_newOwner == address(0)) revert NewOwnerCannotBeZeroAddress();
    owner = _newOwner;
    emit OwnerUpdated(_newOwner);
  }

  /// @notice Prepares the contract for an upgrade
  function setUpgrade() external onlyOwner {
    if (!stopped) {
      stopped = true;
      upgradeTime = block.timestamp + 2 days;
    }
  }

  /// @notice Allows the owner to transfer tokens from the contract
  /// @param _token The address of the token to transfer
  /// @param _to The address to transfer the tokens to
  /// @param _amount The amount of tokens to transfer
  function transferToken(
    address _token,
    address _to,
    uint256 _amount
  ) external onlyOwner {
    bool isProtectedToken = _token == gem || (_token == underlying && evacuated);
    if (_token == MAI_ADDRESS && evacuated) {
      uint256 available = IERC20(MAI_ADDRESS).balanceOf(address(this)) - totalQueuedMAI;
      if (_amount > available) revert NotEnoughLiquidity();
    }
    if (!isProtectedToken || (stopped && block.timestamp > upgradeTime)) {
      IERC20(_token).transfer(_to, _amount);
    } else {
      revert UpgradeNotScheduled();
    }
  }

  /// @notice Allows the owner to withdraw MAI tokens from the contract
  function withdrawMAI() external onlyOwner {
    IERC20 _mai = IERC20(MAI_ADDRESS);
    uint256 balance = _mai.balanceOf(address(this));

    if (evacuated) {
      uint256 available = balance > totalQueuedMAI ? balance - totalQueuedMAI : 0;
      if (available > 0) {
        _mai.transfer(msg.sender, available);
      }
    } else {
      _mai.transfer(msg.sender, balance);
    }
  }

  /// @notice Updates the minimum fees for deposit and withdrawal
  /// @param _newMinimumDepositFee The new minimum deposit fee
  /// @param _newMinimumWithdrawalFee The new minimum withdrawal fee
  function updateMinimumFees(
    uint256 _newMinimumDepositFee,
    uint256 _newMinimumWithdrawalFee
  ) external onlyOwner {
    minimumDepositFee = _newMinimumDepositFee;
    minimumWithdrawalFee = _newMinimumWithdrawalFee;
    emit MinimumFeesUpdated(_newMinimumDepositFee, _newMinimumWithdrawalFee);
  }

  /// @notice Updates the deposit and withdrawal fees in basis points
  /// @param _newDepositFee The new deposit fee in basis points
  /// @param _newWithdrawalFee The new withdrawal fee in basis points
  function updateFeesBP(
    uint256 _newDepositFee,
    uint256 _newWithdrawalFee
  ) external onlyOwner {
    depositFee = _newDepositFee;
    withdrawalFee = _newWithdrawalFee;
    emit FeesUpdated(_newDepositFee, _newWithdrawalFee);
  }

  /// @notice Updates the maximum deposit and withdrawal limits
  /// @param _maxDeposit The new maximum deposit limit
  /// @param _maxWithdraw The new maximum withdrawal limit
  function updateMax(
    uint256 _maxDeposit,
    uint256 _maxWithdraw
  ) external onlyOwner {
    maxDeposit = _maxDeposit;
    maxWithdraw = _maxWithdraw;
    emit MaxUpdated(_maxDeposit, _maxWithdraw);
  }
}
