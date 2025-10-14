// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ICollateralManager} from "./interfaces/ICollateralManager.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {Constants} from "./Constants.sol";

/**
 * @title CollateralManager - Gas Optimized & Security Hardened
 * @dev Optimized for gas efficiency while maintaining full functionality and security
 */
contract CollateralManager is ICollateralManager, ReentrancyGuard {
    // ============ STRUCTS ============

    struct UserCollateral {
        uint128 amount;
        uint128 lastUpdate;
    }

    struct CollateralType {
        address token;
        address priceFeed;
        uint256 fallbackPrice;
        uint8 decimals;
        uint16 ltv; // Loan-to-Value ratio (basis points, e.g., 8000 = 80%)
        uint16 liquidationThreshold; // Liquidation threshold (basis points, e.g., 12000 = 120%)
        uint16 liquidationPenalty; // Liquidation penalty (basis points, e.g., 800 = 8%)
        bool isActive;
    }

    // ============ CONSTANTS ============
    uint256 private constant MAX_UINT128 = type(uint128).max;

    // ============ IMMUTABLES ============
    address public immutable OWNER;
    IPriceOracle public immutable PRICE_ORACLE;

    // ============ STATE VARIABLES ============
    address public stableGuard;
    mapping(address => mapping(address => UserCollateral)) public collateral;
    mapping(address => address[]) public userTokens;
    mapping(address => CollateralType) public collateralTypes;
    address[] public supportedTokens;

    // ============ MODIFIERS ============
    modifier onlyAuth() {
        if (msg.sender != OWNER && msg.sender != stableGuard) revert Unauthorized();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != OWNER) revert Unauthorized();
        _;
    }

    modifier onlyStableGuard() {
        if (msg.sender != stableGuard) revert Unauthorized();
        _;
    }

    modifier validAmount(uint256 amount) {
        if (amount == 0 || amount > MAX_UINT128) revert InvalidAmount();
        _;
    }

    modifier validUser(address user) {
        if (user == address(0)) revert InvalidAddress();
        _;
    }

    // ============ CONSTRUCTOR ============
    constructor(address _priceOracle) {
        if (_priceOracle == address(0)) revert InvalidAddress();
        OWNER = msg.sender;
        PRICE_ORACLE = IPriceOracle(_priceOracle);
    }

    // ============ EXTERNAL FUNCTIONS ============
    function setStableGuard(address _stableGuard) external onlyAuth {
        if (_stableGuard == address(0)) revert InvalidAddress();
        stableGuard = _stableGuard;
    }

    function addCollateralType(
        address token,
        address priceFeed,
        uint256 fallbackPrice,
        uint8 decimals,
        uint16 ltv,
        uint16 liquidationThreshold,
        uint16 liquidationPenalty
    ) external override onlyAuth {
        // CHECKS: Input validation
        if (token == address(0)) revert InvalidAddress();
        if (priceFeed == address(0)) revert InvalidAddress();
        if (fallbackPrice == 0) revert InvalidAmount();
        if (ltv == 0 || ltv > 10000) revert InvalidAmount(); // Max 100%
        if (liquidationThreshold == 0 || liquidationThreshold > 15000) revert InvalidAmount(); // Max 150%
        if (liquidationThreshold <= ltv) revert InvalidAmount(); // Liquidation threshold must be higher than LTV
        if (liquidationPenalty == 0 || liquidationPenalty > 2000) revert InvalidAmount(); // Max 20%

        // Check if token is already supported
        if (collateralTypes[token].isActive) revert InvalidAddress(); // Reusing error for "already exists"

        // EFFECTS: Add collateral type
        collateralTypes[token] = CollateralType({
            token: token,
            priceFeed: priceFeed,
            fallbackPrice: fallbackPrice,
            decimals: decimals,
            ltv: ltv,
            liquidationThreshold: liquidationThreshold,
            liquidationPenalty: liquidationPenalty,
            isActive: true
        });

        supportedTokens.push(token);
    }

    function deposit(address user, address token, uint256 amount)
        external
        payable
        override
        onlyStableGuard
        validUser(user)
        validAmount(amount)
        nonReentrant
    {
        // CHECKS: Input validation
        if (!PRICE_ORACLE.isSupportedToken(token)) revert UnsupportedToken();

        // INTERACTIONS: For ETH, enforce msg.value; for ERC20, StableGuard transfers beforehand
        if (token == Constants.ETH_TOKEN) {
            if (msg.value != amount) revert ETHMismatch();
        } else {
            if (msg.value != 0) revert ETHMismatch();
            // If this contract doesn't yet hold the tokens (e.g., direct deposit flows),
            // pull them from the caller to ensure subsequent withdrawals succeed.
            uint256 bal = IERC20(token).balanceOf(address(this));
            if (bal < amount) {
                bool ok = IERC20(token).transferFrom(msg.sender, address(this), amount);
                if (!ok) revert TransferFailed();
            }
        }

        // EFFECTS: Update state after receiving funds
        _updateCollateral(user, token, amount, true);
        emit Deposit(user, token, amount);
    }

    function withdraw(address user, address token, uint256 amount)
        external
        override
        onlyStableGuard
        validUser(user)
        validAmount(amount)
        nonReentrant
    {
        // CHECKS: Input validation
        UserCollateral storage userCol = collateral[user][token];
        if (userCol.amount < amount) revert InsufficientCollateral();

        // EFFECTS: Update state before external interactions
        _updateCollateral(user, token, amount, false);

        // INTERACTIONS: External transfers at the end
        if (token == Constants.ETH_TOKEN) {
            (bool success,) = msg.sender.call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            bool success = IERC20(token).transfer(msg.sender, amount);
            if (!success) revert TransferFailed();
        }

        emit Withdraw(user, token, amount);
    }

    // ============ VIEW FUNCTIONS ============
    function getUserCollateral(address user, address token) external view override returns (uint256) {
        if (user == address(0)) revert InvalidAddress();
        return collateral[user][token].amount;
    }

    function getUserTokens(address user) external view override returns (address[] memory) {
        if (user == address(0)) revert InvalidAddress();
        return userTokens[user];
    }

    function getTotalCollateralValue(address user) external override returns (uint256 totalValue) {
        if (user == address(0)) revert InvalidAddress();
        address[] memory tokens = userTokens[user];
        uint256 length = tokens.length;

        // Optimization: use unchecked loop
        for (uint256 i; i < length;) {
            address token = tokens[i];
            UserCollateral memory userCol = collateral[user][token]; // Cache entire struct

            if (userCol.amount > 0) {
                try PRICE_ORACLE.getTokenPrice(token) returns (uint256 price) {
                    // Additional validation: price must be > 0
                    if (price > 0) {
                        totalValue += (price * userCol.amount) / 1e18;
                    }
                } catch {
                    // Skip tokens with failed price calls
                }
            }

            unchecked {
                ++i;
            } // Gas saving
        }
    }

    function canLiquidate(address user, uint256 debtValue, uint256 liquidationThreshold)
        external
        override
        returns (bool)
    {
        // CHECKS: Input validation
        if (user == address(0)) revert InvalidAddress();
        if (liquidationThreshold == 0 || liquidationThreshold > 15000) revert InvalidAmount(); // Max 150%

        // Avoid multiplication overflow
        if (debtValue == 0) return false;

        uint256 collateralValue = this.getTotalCollateralValue(user);

        // Overflow protection: divide instead of multiply where possible
        return collateralValue < (debtValue * liquidationThreshold) / 10000;
    }

    // ============ INTERNAL FUNCTIONS ============
    function _updateCollateral(address user, address token, uint256 amount, bool isDeposit) internal {
        UserCollateral storage userCol = collateral[user][token];

        if (isDeposit) {
            if (userCol.amount == 0) {
                userTokens[user].push(token);
            }
            userCol.amount += uint128(amount);
        } else {
            userCol.amount -= uint128(amount);
            if (userCol.amount == 0) {
                _removeUserToken(user, token);
            }
        }

        userCol.lastUpdate = uint128(block.timestamp);
    }

    function _removeUserToken(address user, address token) internal {
        address[] storage tokens = userTokens[user];
        uint256 length = tokens.length;

        for (uint256 i; i < length; ++i) {
            if (tokens[i] == token) {
                tokens[i] = tokens[length - 1];
                tokens.pop();
                break;
            }
        }
    }

    // ============ EMERGENCY FUNCTIONS ============
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner nonReentrant {
        // CHECKS: Robust validations
        if (amount == 0) revert InvalidAmount();

        // Verify available balance
        uint256 availableBalance;
        if (token == Constants.ETH_TOKEN) {
            availableBalance = address(this).balance;
        } else {
            if (token == address(0)) revert InvalidAddress();
            availableBalance = IERC20(token).balanceOf(address(this));
        }

        if (amount > availableBalance) revert InsufficientCollateral();

        // INTERACTIONS: External transfers
        if (token == Constants.ETH_TOKEN) {
            (bool success,) = OWNER.call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            bool success = IERC20(token).transfer(OWNER, amount);
            if (!success) revert TransferFailed();
        }
    }

    receive() external payable {
        if (msg.sender != stableGuard) revert Unauthorized();
    }
}
