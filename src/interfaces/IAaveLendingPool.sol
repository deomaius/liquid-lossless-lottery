pragma solidity ^0.8.20;

interface IAaveLendingPool {
      // Struct returned by getReserveData
    struct ReserveData {
        // Configuration bitmap
        uint256 configuration;
        // Liquidity index (ray, 1e27)
        uint128 liquidityIndex;
        // Variable borrow index (ray, 1e27)
        uint128 variableBorrowIndex;
        // Current liquidity rate (ray, 1e27)
        uint128 currentLiquidityRate;
        // Current variable borrow rate (ray, 1e27)
        uint128 currentVariableBorrowRate;
        // Current stable borrow rate (ray, 1e27)
        uint128 currentStableBorrowRate;
        // Timestamp of last update
        uint40 lastUpdateTimestamp;
        // Address of the aToken contract
        address aTokenAddress;
        // Address of the stable debt token
        address stableDebtTokenAddress;
        // Address of the variable debt token
        address variableDebtTokenAddress;
        // Address of the interest rate strategy
        address interestRateStrategyAddress;
        // Reserve ID
        uint8 id;
    }

    function getReserveData(address asset) external view returns (ReserveData memory);

    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}
