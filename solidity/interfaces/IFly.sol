pragma solidity 0.8.19;

interface IFly {
  function allowance(address owner, address spender) external view returns (uint256);
  function approve(address spender, uint256 value) external returns (bool);
  function asset() external view returns (address);
  function balanceOf(address account) external view returns (uint256);
  function convertToAssets(uint256 shares) external view returns (uint256);
  function convertToShares(uint256 assets) external view returns (uint256);
  function decimals() external view returns (uint8);
  function deposit(uint256 assets, address receiver) external returns (uint256);
  function initialize() external;
  function maxDeposit(address) external view returns (uint256);
  function maxMint(address) external view returns (uint256);
  function maxRedeem(address owner) external view returns (uint256);
  function maxWithdraw(address owner) external view returns (uint256);
  function mint(uint256 shares, address receiver) external returns (uint256);
  function name() external view returns (string memory);
  function previewDeposit(uint256 assets) external view returns (uint256);
  function previewMint(uint256 shares) external view returns (uint256);
  function previewRedeem(uint256 shares) external view returns (uint256);
  function previewWithdraw(uint256 assets) external view returns (uint256);
  function redeem(uint256 shares, address receiver, address owner) external returns (uint256);
  function symbol() external view returns (string memory);
  function totalAssets() external view returns (uint256);
  function totalSupply() external view returns (uint256);
  function transfer(address to, uint256 value) external returns (bool);
  function transferFrom(address from, address to, uint256 value) external returns (bool);
  function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);
}
