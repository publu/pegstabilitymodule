// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IBeefy} from 'interfaces/IBeefy.sol';
import {IERC20} from 'interfaces/IERC20.sol';

/// @title BeefyVaultPSMV2
/// @notice PSM with configurable MAI address, minimum reserves, and evacuate/sweep/multi-guardian
/// @dev V2 of BeefyVaultPSM. Strict superset of V1 (was named BeefyVaultPSMMainnet before V1/V2 split).
contract BeefyVaultPSMV2 {
  uint256 public constant MAX_INT =
    115_792_089_237_316_195_423_570_985_008_687_907_853_269_984_665_640_564_039_457_584_007_913_129_639_935;

  // Configurable MAI address (not hardcoded like base chain version)
  address public MAI_ADDRESS;

  uint256 public totalStableLiquidity;
  uint256 public totalQueuedLiquidity;
  uint256 public depositFee;
  uint256 public withdrawalFee;
  uint256 public minimumDepositFee;
  uint256 public minimumWithdrawalFee;
  uint256 public decimalDifference;

  // Minimum reserves - absolute amount in underlying decimals (6 for USDC)
  uint256 public minimumReserves;

  uint256 public maxDeposit;
  uint256 public maxWithdraw;
  uint256 public upgradeTime;

  address public underlying;
  address public owner;
  address public gem;

  // user deposits stable, schedules withdrawal of shares
  mapping(address => uint256) public withdrawalEpoch;
  mapping(address => uint256) public scheduledWithdrawalAmount;

  mapping(bytes4 => bool) public paused;
  bool public stopped;

  bool public initialized;

  bool public evacuated;
  mapping(address => bool) public guardians;
  uint256 public totalQueuedMAI;
  uint256 public evacuationTime;
  uint256 public constant SETTLEMENT_TIMEOUT = 30 days;

  error CallerIsNotOwner();
  error CallerIsNotGuardianOrOwner();
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
  error GuardianCannotBeZeroAddress();
  error WithdrawalNotAvailable();
  error NotEnoughLiquidity();
  error NotEvacuated();
  error UpgradeNotScheduled();
  error SettlementTooEarly();
  error MAIAddressCannotBeZero();
  error MinimumReservesBreached();

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
  event MinimumReservesUpdated(uint256 _oldMinimumReserves, uint256 _newMinimumReserves);
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

  /// @notice Initialize the PSM with vault and fee configuration
  /// @param _gem The Beefy vault address
  /// @param _depositFee Deposit fee in basis points
  /// @param _withdrawalFee Withdrawal fee in basis points
  /// @param _maiAddress The MAI token address for this chain
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

    depositFee = _depositFee; // basis points
    withdrawalFee = _withdrawalFee; // basis points
    minimumDepositFee = 1_000_000; // this is 1 dollar (in 6 decimals)
    minimumWithdrawalFee = 1_000_000; // 1 dollar

    IBeefy _beef = IBeefy(_gem);

    maxDeposit = 1e24; // 1 million ether
    maxWithdraw = 1e24; // 1 million ether
    underlying = _beef.want();
    decimalDifference = uint256(_beef.decimals() - IERC20(underlying).decimals());
    gem = _gem;
    MAI_ADDRESS = _maiAddress;
    minimumReserves = 0; // Default to 0, owner can set later
    initialized = true;
    approveBeef();
  }

  function approveBeef() public {
    IERC20(underlying).approve(gem, MAX_INT);
  }

  /// @notice User deposits underlying tokens and receives MAI
  /// @param _amount The amount of underlying tokens to deposit (6 decimals for USDC)
  function deposit(
    uint256 _amount
  ) external pausable {
    if (_amount <= minimumDepositFee || _amount > maxDeposit) revert InvalidAmount();
    IERC20(underlying).transferFrom(msg.sender, address(this), _amount);
    uint256 _fee = calculateFee(_amount, true);
    _amount = _amount - _fee;
    totalStableLiquidity += _amount;
    IBeefy(gem).depositAll();

    uint256 _maiOut = _amount * (10 ** (decimalDifference));
    if (IERC20(MAI_ADDRESS).balanceOf(address(this)) < totalQueuedMAI + _maiOut) {
      revert InsufficientMAIBalance();
    }
    IERC20(MAI_ADDRESS).transfer(msg.sender, _maiOut);
    emit Deposited(msg.sender, _amount);
  }

  /// @notice Schedule a withdrawal of MAI for underlying tokens
  /// @param _amount The amount of MAI to withdraw (18 decimals)
  function scheduleWithdraw(
    uint256 _amount
  ) external pausable {
    if (withdrawalEpoch[msg.sender] != 0) {
      revert WithdrawalAlreadyScheduled();
    }

    uint256 _toWithdraw = _amount / (10 ** decimalDifference);
    uint256 _fee = calculateFee(_toWithdraw, false);
    if (_toWithdraw <= _fee) revert InvalidAmountAfterFee();

    if (_amount < minimumWithdrawalFee || _amount > maxWithdraw) revert InvalidAmount();

    // Check minimum reserves constraint
    // Available = totalStableLiquidity - totalQueuedLiquidity
    // After this withdrawal: Available - _toWithdraw must be >= minimumReserves
    uint256 _availableLiquidity = totalStableLiquidity - totalQueuedLiquidity;
    if (_availableLiquidity < minimumReserves + _toWithdraw) {
      revert MinimumReservesBreached();
    }

    totalQueuedLiquidity += _toWithdraw;
    totalQueuedMAI += _amount;
    scheduledWithdrawalAmount[msg.sender] = _amount;

    IERC20(MAI_ADDRESS).transferFrom(msg.sender, address(this), _amount);

    withdrawalEpoch[msg.sender] = block.timestamp + 3 days;
    emit WithdrawalScheduled(msg.sender, _amount);
  }

  function _calculateAmountToShares(
    uint256 _amount
  ) internal view returns (uint256 _shares) {
    IBeefy _beef = IBeefy(gem);
    return (_amount * _beef.totalSupply()) / _beef.balance();
  }

  function _calculateSharesToAmount(
    uint256 _shares
  ) internal view returns (uint256 _amount) {
    IBeefy _beef = IBeefy(gem);
    return (_shares * _beef.balance()) / _beef.totalSupply();
  }

  /// @notice Execute a scheduled withdrawal. Blocked post-evacuation by pausable modifier.
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

    IBeefy _beef = IBeefy(gem);
    uint256 _freshShares = _calculateAmountToShares(_amount);
    uint256 _freshSharesRounded = (_freshShares / (10 ** decimalDifference));
    _beef.withdraw(_freshSharesRounded);
    IERC20(underlying).transfer(msg.sender, _toWithdrawwFee);
    _beef.depositAll();

    totalStableLiquidity -= _toWithdraw;
    totalQueuedLiquidity -= _toWithdraw;
    totalQueuedMAI -= _amount;

    emit Withdrawn(msg.sender, _amount);
  }

  /// @notice Calculate the fee for a deposit or withdrawal
  /// @param _amount The amount to calculate fee on (in underlying decimals)
  /// @param _deposit True for deposit fee, false for withdrawal fee
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

  /// @notice Returns the amount available for new withdrawal scheduling
  /// @return The amount in underlying decimals (6 for USDC) that can be withdrawn
  function availableForWithdrawal() public view returns (uint256) {
    uint256 _availableLiquidity = totalStableLiquidity - totalQueuedLiquidity;
    if (_availableLiquidity <= minimumReserves) {
      return 0;
    }
    uint256 _available = _availableLiquidity - minimumReserves;
    // Clamp to amounts that survive the withdrawal fee floor
    uint256 _fee = calculateFee(_available, false);
    if (_available <= _fee) {
      return 0;
    }
    return _available;
  }

  /// @notice Returns the amount available for withdrawal scheduling in MAI decimals
  /// @return The amount in MAI decimals (18) that can be withdrawn
  function availableForWithdrawalInMAI() external view returns (uint256) {
    return availableForWithdrawal() * (10 ** decimalDifference);
  }

  /// @notice Owner can claim accumulated fees (yield above liabilities)
  function claimFees() external onlyOwner {
    if (evacuated) return;
    IBeefy _beef = IBeefy(gem);
    // get total balance in underlying
    uint256 _shares = _beef.balanceOf(address(this));
    uint256 _totalStoredInUsd = _calculateSharesToAmount(_shares);
    uint256 _totalStableShares = _calculateAmountToShares(totalStableLiquidity);
    if (_totalStoredInUsd > totalStableLiquidity) {
      uint256 _fees = (_totalStoredInUsd - totalStableLiquidity); // in USDC
      _beef.withdraw(_shares - _totalStableShares);
      emit FeesWithdrawn(msg.sender, _fees);
      IERC20 usdc = IERC20(underlying);
      usdc.transfer(msg.sender, usdc.balanceOf(address(this)));
    }
  }

  /// @notice Set the minimum reserves that must remain available in the PSM
  /// @param _minimumReserves The minimum amount in underlying token decimals (6 for USDC)
  function setMinimumReserves(
    uint256 _minimumReserves
  ) external onlyOwner {
    uint256 _oldMinimumReserves = minimumReserves;
    minimumReserves = _minimumReserves;
    emit MinimumReservesUpdated(_oldMinimumReserves, _minimumReserves);
  }

  /// @notice Emergency evacuation: withdraws all assets from the Beefy vault and freezes the contract
  function evacuateVault() external onlyGuardianOrOwner {
    evacuated = true;
    if (evacuationTime == 0) evacuationTime = block.timestamp;

    if (!stopped) {
      stopped = true;
      upgradeTime = block.timestamp + 2 days;
    }

    uint256 totalShares = IBeefy(gem).balanceOf(address(this));
    if (totalShares > 0) {
      try IBeefy(gem).withdrawAll() {}
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

  /// @notice Owner can force-settle a stale queued entry after SETTLEMENT_TIMEOUT
  function forceSettle(
    address _user
  ) external onlyOwner {
    if (!evacuated) revert NotEvacuated();
    if (block.timestamp < evacuationTime + SETTLEMENT_TIMEOUT) revert SettlementTooEarly();
    uint256 amount = scheduledWithdrawalAmount[_user];
    if (amount == 0) revert NoWithdrawalScheduled();

    uint256 toRefund = amount / (10 ** decimalDifference);

    scheduledWithdrawalAmount[_user] = 0;
    withdrawalEpoch[_user] = 0;
    totalQueuedLiquidity -= toRefund;
    totalStableLiquidity -= toRefund;
    totalQueuedMAI -= amount;

    // Send MAI directly to the user's address
    IERC20(MAI_ADDRESS).transfer(_user, amount);
    emit RefundClaimed(_user, amount);
  }

  /// @notice Deposits idle USDC in the contract into the Beefy vault with correct bookkeeping
  function sweep() external onlyOwner {
    if (evacuated) revert ContractIsPaused();

    uint256 balance = IERC20(underlying).balanceOf(address(this));
    if (balance == 0) revert InvalidAmount();

    IBeefy(gem).depositAll();
    totalStableLiquidity += balance;

    emit Swept(msg.sender, balance);
  }

  /// @notice Adds or removes a guardian address for emergency evacuation
  function setGuardian(
    address _guardian,
    bool _enabled
  ) external onlyOwner {
    if (_enabled && _guardian == address(0)) revert GuardianCannotBeZeroAddress();
    guardians[_guardian] = _enabled;
    emit GuardianUpdated(_guardian, _enabled);
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
    owner = _newOwner;
    emit OwnerUpdated(_newOwner);
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
    // MAI: reserve totalQueuedMAI
    if (_token == MAI_ADDRESS) {
      uint256 balance = IERC20(MAI_ADDRESS).balanceOf(address(this));
      uint256 available = balance > totalQueuedMAI ? balance - totalQueuedMAI : 0;
      if (_amount > available) revert NotEnoughLiquidity();
    }
    // underlying: NO reservation needed — users get MAI not USDC
    bool isProtectedToken = _token == gem || (_token == underlying && evacuated);
    if (!isProtectedToken || (stopped && block.timestamp > upgradeTime)) {
      IERC20(_token).transfer(_to, _amount);
    } else {
      revert UpgradeNotScheduled();
    }
  }

  function withdrawMAI() external onlyOwner {
    IERC20 _mai = IERC20(MAI_ADDRESS);
    uint256 balance = _mai.balanceOf(address(this));

    uint256 available = balance > totalQueuedMAI ? balance - totalQueuedMAI : 0;
    if (available > 0) {
      _mai.transfer(msg.sender, available);
    }
  }

  function updateMinimumFees(
    uint256 _newMinimumDepositFee,
    uint256 _newMinimumWithdrawalFee
  ) external onlyOwner {
    minimumDepositFee = _newMinimumDepositFee;
    minimumWithdrawalFee = _newMinimumWithdrawalFee;
    emit MinimumFeesUpdated(_newMinimumDepositFee, _newMinimumWithdrawalFee);
  }

  function updateFeesBP(
    uint256 _newDepositFee,
    uint256 _newWithdrawalFee
  ) external onlyOwner {
    depositFee = _newDepositFee;
    withdrawalFee = _newWithdrawalFee;
    emit FeesUpdated(_newDepositFee, _newWithdrawalFee);
  }

  function updateMax(
    uint256 _maxDeposit,
    uint256 _maxWithdraw
  ) external onlyOwner {
    maxDeposit = _maxDeposit;
    maxWithdraw = _maxWithdraw;
    emit MaxUpdated(_maxDeposit, _maxWithdraw);
  }
}
