// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title ICollateralManager - Ultra-Optimized Interface
 * @dev Minimal gas-optimized interface for collateral management
 */
interface ICollateralManager {
    // ============ ERRORS ============
    error Unauthorized();
    error InvalidAddress();
    error InvalidAmount();
    error InsufficientCollateral();
    error TransferFailed();
    error UnsupportedToken();
    error ETHMismatch();

    // ============ EVENTS ============

    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);

    // ============ CORE FUNCTIONS ============

    /// @dev Add a new collateral type
    function addCollateralType(
        address token,
        address priceFeed,
        uint256 fallbackPrice,
        uint8 decimals,
        uint16 ltv,
        uint16 liquidationThreshold,
        uint16 liquidationPenalty
    ) external;

    /// @dev Unified deposit for ETH and ERC20 tokens
    function deposit(address user, address token, uint256 amount) external payable;

    /// @dev Unified withdraw for ETH and ERC20 tokens
    function withdraw(address user, address token, uint256 amount) external;

    // ============ VIEW FUNCTIONS ============

    function getUserCollateral(address user, address token) external view returns (uint256);
    function getUserTokens(address user) external view returns (address[] memory);
    function getTotalCollateralValue(address user) external returns (uint256);
    function canLiquidate(address user, uint256 debtValue, uint256 liquidationThreshold) external returns (bool);
    function emergencyWithdraw(address token, uint256 amount) external;
}
