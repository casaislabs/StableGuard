// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title ILiquidationManager - Ultra-Optimized Interface
 * @dev Minimal gas-optimized interface for liquidation management
 */
interface ILiquidationManager {
    // ============ EVENTS ============

    /// @dev Event emitted when a liquidation occurs
    event LiquidationEvent(
        address indexed liquidator,
        address indexed user,
        address indexed token,
        uint256 debtAmount,
        uint256 liquidationAmount
    );

    // ============ ERRORS ============
    error Unauthorized();
    error InvalidAmount();
    error InvalidAddress();
    error NoCollateral();

    // ============ CORE FUNCTIONS ============

    /// @dev Liquidate user position with optimal token selection
    function liquidate(address user, uint256 debtAmount) external returns (bool);

    /// @dev Liquidate user position with specific token
    function liquidate(address user, address token, uint256 debtAmount) external returns (bool);

    /// @dev Direct liquidation (owner only)
    function liquidateDirect(address user, uint256 debtAmount) external returns (bool);

    /// @dev Direct liquidation with specific token (owner only)
    function liquidateDirect(address user, address token, uint256 debtAmount) external returns (bool);

    // ============ VIEW FUNCTIONS ============

    /// @dev Check if position is liquidatable
    function isLiquidatable(address user) external returns (bool);

    /// @dev Calculate liquidation amounts
    function calculateLiquidationAmounts(address user, address token, uint256 debtAmount)
        external
        returns (uint256 collateralAmount, uint256 liquidationBonus);

    /// @dev Get collateral ratio for user
    function getCollateralRatio(address user) external returns (uint256);

    /// @dev Find optimal token for liquidation
    function findOptimalToken(address user) external returns (address optimalToken);

    /// @dev Check if position is safe
    function isPositionSafe(address user, uint256 collateralValue, bool useMinRatio) external view returns (bool);

    /// @dev Calculate collateral from debt
    function calculateCollateralFromDebt(uint256 debtValue, uint256 tokenPrice) external view returns (uint256);

    /// @dev Find optimal token for liquidation (alternative signature)
    function findOptimalTokenForLiquidation(address user) external returns (address);

    /// @dev Get liquidation constants
    function getLiquidationConstants() external pure returns (uint256, uint256, uint256);
}
