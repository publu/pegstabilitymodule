pragma solidity 0.8.19;

interface IERC20 {
  function approve(address _spender, uint256 _amount) external returns (bool _success);
  function transfer(address _recipient, uint256 _amount) external returns (bool _success);
  function transferFrom(address _sender, address _recipient, uint256 _amount) external returns (bool _success);
  function balanceOf(address _account) external view returns (uint256 _balance);
  function decimals() external view returns (uint8 decimals);
}
