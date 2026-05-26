pragma solidity 0.8.19;

interface IAavePool {
  struct ReserveConfigurationMap {
    uint256 data;
  }

  struct ReserveDataLegacy {
    ReserveConfigurationMap configuration;
    uint128 liquidityIndex;
    uint128 currentLiquidityRate;
    uint128 variableBorrowIndex;
    uint128 currentVariableBorrowRate;
    uint128 currentStableBorrowRate;
    uint40 lastUpdateTimestamp;
    uint16 id;
    address aTokenAddress;
    address stableDebtTokenAddress;
    address variableDebtTokenAddress;
    address interestRateStrategyAddress;
    uint128 accruedToTreasury;
    uint128 unbacked;
    uint128 isolationModeTotalDebt;
  }

  function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
  function withdraw(address asset, uint256 amount, address to) external returns (uint256);
  function getReserveData(address asset) external view returns (ReserveDataLegacy memory);
}

interface IAToken {
  function POOL() external view returns (address);
  function UNDERLYING_ASSET_ADDRESS() external view returns (address);
  function balanceOf(address user) external view returns (uint256);
  function decimals() external view returns (uint8);
}
