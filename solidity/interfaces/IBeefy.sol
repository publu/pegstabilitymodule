pragma solidity 0.8.19;

interface IBeefy {
  function getPricePerFullShare() external view returns (uint256 _pricePerFullShare);
  function allowance(address _owner, address _spender) external view returns (uint256);
  function approvalDelay() external view returns (uint256);
  function approve(address _spender, uint256 _amount) external returns (bool);
  function available() external view returns (uint256);
  function balance() external view returns (uint256);
  function balanceOf(address _account) external view returns (uint256);
  function decimals() external view returns (uint8);
  function decreaseAllowance(address _spender, uint256 _subtractedValue) external returns (bool);
  function deposit(uint256 _amount) external;
  function depositAll() external;
  function inCaseTokensGetStuck(address _token) external;
  function increaseAllowance(address _spender, uint256 _addedValue) external returns (bool);
  function initialize(
    address _strategy,
    string calldata _name,
    string calldata _symbol,
    uint256 _approvalDelay
  ) external;
  function name() external view returns (string memory);
  function owner() external view returns (address);
  function proposeStrat(address _implementation) external;
  function renounceOwnership() external;
  function stratCandidate() external view returns (address implementation, uint256 proposedTime);
  function strategy() external view returns (address);
  function symbol() external view returns (string memory);
  function totalSupply() external view returns (uint256);
  function want() external view returns (address);
  function withdraw(uint256 _shares) external;
  function withdrawAll() external;
}
