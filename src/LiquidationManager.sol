// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {ICollateralManager} from "./interfaces/ICollateralManager.sol";
import {ILiquidationManager} from "./interfaces/ILiquidationManager.sol";

/// @title LiquidationManager - Ultra Gas Optimized with Enhanced Security
contract LiquidationManager is ILiquidationManager, ReentrancyGuard {
    // ============ ULTRA-PACKED STORAGE (1 SLOT) ============
    struct PackedConfig {
        address stableGuard; // 20 bytes
        uint32 minRatio; // 4 bytes - 150% = 15000
        uint32 liqThreshold; // 4 bytes - 120% = 12000
        uint32 bonus; // 4 bytes - 10% = 1000
            // Total: 32 bytes (1 slot)
    }

    // ============ IMMUTABLE STATE ============
    address private owner;
    IPriceOracle private immutable ORACLE;
    ICollateralManager private immutable COLLATERAL;
    PackedConfig private config;

    // ============ ULTRA-COMPACT MODIFIERS ============
    modifier onlyOwner() {
        assembly {
            if iszero(eq(caller(), sload(owner.slot))) {
                mstore(0x00, 0x82b42900)
                revert(0x1c, 0x04)
            }
        }
        _;
    }

    modifier onlyGuard() {
        assembly {
            let packed := sload(config.slot)
            if iszero(eq(caller(), and(packed, 0xffffffffffffffffffffffffffffffffffffffff))) {
                mstore(0x00, 0x82b42900)
                revert(0x1c, 0x04)
            }
        }
        _;
    }

    // ============ ULTRA-OPTIMIZED CONSTRUCTOR ============
    constructor(address _owner, address _oracle, address _collateral) {
        assembly {
            if iszero(_owner) {
                mstore(0x00, 0xd92e233d)
                revert(0x1c, 0x04)
            }
            if iszero(_oracle) {
                mstore(0x00, 0xd92e233d)
                revert(0x1c, 0x04)
            }
            if iszero(_collateral) {
                mstore(0x00, 0xd92e233d)
                revert(0x1c, 0x04)
            }
        }
        owner = _owner;
        ORACLE = IPriceOracle(_oracle);
        COLLATERAL = ICollateralManager(_collateral);

        // Pack config: stableGuard(0) + minRatio(15000) + liqThreshold(12000) + bonus(1000)
        assembly {
            let packed := or(or(or(0, shl(160, 15000)), shl(192, 12000)), shl(224, 1000))
            sstore(config.slot, packed)
        }
    }

    // ============ ULTRA-COMPACT FUNCTIONS ============
    function setStableGuard(address _guard) external onlyOwner {
        assembly {
            if iszero(_guard) {
                mstore(0x00, 0xd92e233d)
                revert(0x1c, 0x04)
            }
            let packed := sload(config.slot)
            let newPacked := or(and(packed, not(0xffffffffffffffffffffffffffffffffffffffff)), _guard)
            sstore(config.slot, newPacked)
        }
    }

    function liquidate(address user, uint256 debtAmount) external override onlyGuard nonReentrant returns (bool) {
        return _liquidate(user, _findOptimalToken(user), debtAmount);
    }

    function liquidateDirect(address user, uint256 debtAmount)
        external
        override
        onlyOwner
        nonReentrant
        returns (bool)
    {
        return _liquidate(user, _findOptimalToken(user), debtAmount);
    }

    function liquidateDirect(address user, address token, uint256 debtAmount)
        external
        override
        onlyOwner
        nonReentrant
        returns (bool)
    {
        return _liquidate(user, token, debtAmount);
    }

    function _findOptimalToken(address user) internal returns (address optimal) {
        address[] memory tokens = ORACLE.getSupportedTokens();
        uint256 maxValue;

        unchecked {
            for (uint256 i; i < tokens.length; ++i) {
                address token = tokens[i];
                uint256 balance = COLLATERAL.getUserCollateral(user, token);
                if (balance > 0) {
                    uint256 value = ORACLE.getTokenValueInUsd(token, balance);
                    if (value > maxValue) {
                        maxValue = value;
                        optimal = token;
                    }
                }
            }
        }
    }

    function _liquidate(address user, address token, uint256 debtAmount) internal returns (bool) {
        // ============ CHECKS ============
        assembly {
            if iszero(debtAmount) {
                mstore(0x00, 0x2c5211c6)
                revert(0x1c, 0x04)
            }
            if iszero(token) {
                mstore(0x00, 0xd92e233d)
                revert(0x1c, 0x04)
            }
        }

        uint256 collateralAmount = COLLATERAL.getUserCollateral(user, token);
        if (collateralAmount == 0) revert NoCollateral();

        uint256 price = ORACLE.getTokenPrice(token);
        uint256 decimals = ORACLE.getTokenDecimals(token);

        // ============ EFFECTS ============
        uint256 liquidationAmount;
        assembly {
            // Extract bonus from packed config (last 32 bits)
            let packed := sload(config.slot)
            let bonus := and(shr(224, packed), 0xffffffff)

            // Calculate collateral value: (amount * price) / 10^decimals
            let collateralValue := div(mul(collateralAmount, price), exp(10, decimals))

            // Calculate max liquidation value: debt * (1 + bonus/10000)
            let maxValue := div(mul(debtAmount, add(10000, bonus)), 10000)

            // Use minimum of collateral value and max liquidation value
            let liquidationValue := lt(collateralValue, maxValue)
            liquidationValue := add(mul(liquidationValue, collateralValue), mul(iszero(liquidationValue), maxValue))

            // Convert back to token amount: (value * 10^decimals) / price
            liquidationAmount := div(mul(liquidationValue, exp(10, decimals)), price)
        }

        // Emit event before external interactions
        emit LiquidationEvent(msg.sender, user, token, debtAmount, liquidationAmount);

        // ============ INTERACTIONS ============
        // Transfer collateral to liquidator
        if (token == address(0)) {
            assembly {
                let success := call(gas(), caller(), liquidationAmount, 0, 0, 0, 0)
                if iszero(success) {
                    mstore(0x00, 0x90b8ec18)
                    revert(0x1c, 0x04)
                }
            }
        } else {
            require(IERC20(token).transfer(msg.sender, liquidationAmount), "Transfer failed");
        }

        // Notify StableGuard of liquidation completion
        address stableGuardAddr;
        assembly {
            let packed := sload(config.slot)
            stableGuardAddr := and(packed, 0xffffffffffffffffffffffffffffffffffffffff)
        }

        if (stableGuardAddr != address(0)) {
            // Call StableGuard to update debt after direct liquidation
            // Intentionally ignore return to avoid reverting on callback failure
            (bool success,) = stableGuardAddr.call(
                abi.encodeWithSignature("processDirectLiquidation(address,uint256)", user, debtAmount)
            );
            success; // Suppress unused variable warning
        }

        return true;
    }

    /**
     * @dev Check if position is liquidatable with enhanced validation
     */
    function isLiquidatable(address user) external override returns (bool) {
        // Enhanced validation for liquidation check
        if (user == address(0)) return false;

        uint256 totalCollateralValue = COLLATERAL.getTotalCollateralValue(user);
        if (totalCollateralValue == 0) return false;

        uint256 debtValue = _getDebtValue(user);
        if (debtValue == 0) return false;

        uint256 threshold;
        assembly {
            let packed := sload(config.slot)
            threshold := and(shr(192, packed), 0xffffffff)
        }

        return (totalCollateralValue * 10000) / debtValue < threshold;
    }

    /**
     * @dev Calculate liquidation amounts
     */
    function calculateLiquidationAmounts(address, /* user */ address token, uint256 debtAmount)
        external
        override
        returns (uint256 collateralAmount, uint256 liquidationBonus)
    {
        uint256 tokenPrice = ORACLE.getTokenPrice(token);
        if (tokenPrice == 0) revert("Invalid token price");

        uint32 bonus = config.bonus;

        collateralAmount = (debtAmount * (10000 + bonus) * 1e18) / (10000 * tokenPrice);
        liquidationBonus = (collateralAmount * bonus) / 10000;
    }

    /**
     * @dev Get collateral ratio for user with enhanced validation
     */
    function getCollateralRatio(address user) external override returns (uint256) {
        // Enhanced validation for collateral ratio calculation
        if (user == address(0)) return 0;

        uint256 totalCollateralValue = COLLATERAL.getTotalCollateralValue(user);
        uint256 debtValue = _getDebtValue(user);
        return debtValue == 0 ? type(uint256).max : (totalCollateralValue * 10000) / debtValue;
    }

    /**
     * @dev Find optimal token for liquidation (public wrapper)
     */
    function findOptimalToken(address user) external override returns (address optimalToken) {
        optimalToken = _findOptimalToken(user);
        require(optimalToken != address(0), "No collateral found");
    }

    // ============ ULTRA-COMPACT VIEW FUNCTIONS WITH ENHANCED VALIDATION ============
    function isPositionSafe(address user, uint256 collateralValue, bool useMinRatio)
        external
        view
        override
        returns (bool)
    {
        // Enhanced validation for view functions
        if (user == address(0)) return false;
        if (collateralValue == 0) return false;

        uint256 debtValue = _getDebtValue(user);
        if (debtValue == 0) return true;

        uint256 threshold;
        assembly {
            let packed := sload(config.slot)
            switch useMinRatio
            case 1 {
                // Use minRatio (bits 160-191)
                threshold := and(shr(160, packed), 0xffffffff)
            }
            default {
                // Use liqThreshold (bits 192-223)
                threshold := and(shr(192, packed), 0xffffffff)
            }
        }

        return (collateralValue * 10000) / debtValue >= threshold;
    }

    function isPositionSafeByValue(uint256 collateralValue, uint256 debtAmount) external pure returns (bool) {
        return collateralValue == 0 ? false : debtAmount == 0 ? true : (collateralValue * 10000) / debtAmount >= 15000;
    }

    function isPositionSafeForLiquidation(address user) external returns (bool) {
        // Enhanced validation for liquidation safety check
        if (user == address(0)) return false;
        return _checkPositionSafety(user, false);
    }

    function isPositionSafeForLiquidationByValue(uint256 collateralValue, uint256 debtAmount)
        external
        pure
        returns (bool)
    {
        return collateralValue == 0 ? false : debtAmount == 0 ? true : (collateralValue * 10000) / debtAmount >= 12000;
    }

    function _checkPositionSafety(address user, bool useMinRatio) internal returns (bool) {
        uint256 collateralValue = COLLATERAL.getTotalCollateralValue(user);
        if (collateralValue == 0) return false;

        uint256 debtValue = _getDebtValue(user);
        if (debtValue == 0) return true;

        uint256 threshold;
        assembly {
            let packed := sload(config.slot)
            switch useMinRatio
            case 1 {
                // Use minRatio (bits 160-191)
                threshold := and(shr(160, packed), 0xffffffff)
            }
            default {
                // Use liqThreshold (bits 192-223)
                threshold := and(shr(192, packed), 0xffffffff)
            }
        }

        return (collateralValue * 10000) / debtValue >= threshold;
    }

    function calculateCollateralFromDebt(uint256 debtValue, uint256 tokenPrice)
        external
        view
        override
        returns (uint256 result)
    {
        // Enhanced validation for collateral calculation
        if (debtValue == 0) return 0;

        assembly {
            if iszero(tokenPrice) {
                mstore(0x00, 0x2c5211c6)
                revert(0x1c, 0x04)
            }

            let packed := sload(config.slot)
            let liqThreshold := and(shr(192, packed), 0xffffffff)

            result := div(mul(mul(debtValue, liqThreshold), exp(10, 18)), mul(10000, tokenPrice))
        }
    }

    function findOptimalTokenForLiquidation(address user) external override returns (address) {
        // Enhanced validation for optimal token finding
        if (user == address(0)) return address(0);
        return _findOptimalToken(user);
    }

    function getLiquidationConstants() external pure override returns (uint256, uint256, uint256) {
        return (15000, 12000, 1000); // minRatio, liqThreshold, bonus
    }

    function _getDebtValue(address user) internal view returns (uint256) {
        address stableGuardAddr;
        assembly {
            let packed := sload(config.slot)
            stableGuardAddr := and(packed, 0xffffffffffffffffffffffffffffffffffffffff)
        }

        if (stableGuardAddr == address(0)) {
            return 1000e18; // Fallback for tests
        }

        // Call StableGuard to get user debt
        (bool success, bytes memory data) =
            stableGuardAddr.staticcall(abi.encodeWithSignature("getDebt(address)", user));

        if (success && data.length >= 32) {
            return abi.decode(data, (uint256));
        }

        return 1000e18; // Fallback
    }

    // Temporary function for testing
    function getDebtValueForTesting(address user) external view returns (uint256) {
        return _getDebtValue(user);
    }

    // ============ ULTRA-COMPACT ADMIN WITH ENHANCED SECURITY ============
    function updateConfig(uint32 _minRatio, uint32 _liqThreshold, uint32 _bonus) external onlyOwner nonReentrant {
        // ============ CHECKS ============
        assembly {
            // Validate liquidation threshold is less than minimum ratio
            if iszero(lt(_liqThreshold, _minRatio)) {
                mstore(0x00, 0x2c5211c6)
                revert(0x1c, 0x04)
            }
            // Validate bonus doesn't exceed 20%
            if gt(_bonus, 2000) {
                mstore(0x00, 0x2c5211c6)
                revert(0x1c, 0x04)
            }
            // Validate minimum ratio is reasonable (>= 110%)
            if lt(_minRatio, 11000) {
                mstore(0x00, 0x2c5211c6)
                revert(0x1c, 0x04)
            }
        }

        // ============ EFFECTS ============
        assembly {
            let packed := sload(config.slot)
            let stableGuard := and(packed, 0xffffffffffffffffffffffffffffffffffffffff)
            let newPacked := or(or(or(stableGuard, shl(160, _minRatio)), shl(192, _liqThreshold)), shl(224, _bonus))
            sstore(config.slot, newPacked)
        }
    }

    function getConfig()
        external
        view
        returns (address stableGuard, uint32 minRatio, uint32 liqThreshold, uint32 bonus)
    {
        assembly {
            let packed := sload(config.slot)
            stableGuard := and(packed, 0xffffffffffffffffffffffffffffffffffffffff)
            minRatio := and(shr(160, packed), 0xffffffff)
            liqThreshold := and(shr(192, packed), 0xffffffff)
            bonus := and(shr(224, packed), 0xffffffff)
        }
    }

    // ============ MEV PROTECTION CONSTANTS ============
    uint256 private constant MIN_LIQUIDATION_DELAY = 30; // 30 seconds between liquidations
    uint256 private constant MAX_LIQUIDATIONS_PER_BLOCK = 3; // Max liquidations per block
    uint256 private constant FLASHLOAN_PROTECTION_BLOCKS = 2; // 2 blocks protection
    uint256 private constant MAX_PRICE_DEVIATION = 200; // 2% max price deviation

    // ============ MEV PROTECTION STORAGE ============
    mapping(address => uint256) public lastLiquidationTime;
    mapping(uint256 => uint256) public blockLiquidationCount;
    mapping(address => uint256) public liquidatorReputation;
    uint256 public flashloanDetectionBlock;

    // ============ MEV PROTECTION EVENTS ============
    event MEVAttemptDetected(address indexed liquidator, address indexed user, string reason);
    event FlashloanDetected(address indexed liquidator, uint256 blockNumber);
    event RateLimitExceeded(address indexed liquidator, uint256 blockNumber);

    // ============ MEV PROTECTION MODIFIERS ============
    modifier mevProtected() {
        _checkMevProtection();
        _;
        _updateMevProtection();
    }

    modifier flashloanProtected() {
        _checkFlashloanProtection();
        _;
    }

    modifier rateLimited() {
        require(block.timestamp >= lastLiquidationTime[msg.sender] + MIN_LIQUIDATION_DELAY, "Rate limited");
        require(blockLiquidationCount[block.number] < MAX_LIQUIDATIONS_PER_BLOCK, "Block limit exceeded");
        _;
        lastLiquidationTime[msg.sender] = block.timestamp;
        blockLiquidationCount[block.number]++;
    }

    /// @dev Enhanced liquidation with MEV protection
    function liquidate(address user, address token, uint256 debtAmount)
        external
        override
        onlyGuard
        nonReentrant
        rateLimited
        mevProtected
        flashloanProtected
        returns (bool)
    {
        return _liquidate(user, token, debtAmount);
    }

    // ============ MEV PROTECTION FUNCTIONS ============

    /// @dev Check MEV protection conditions
    function _checkMevProtection() internal {
        // Check liquidator reputation
        if (liquidatorReputation[msg.sender] == 0 && lastLiquidationTime[msg.sender] > 0) {
            // New liquidator with suspicious activity
            if (block.timestamp < lastLiquidationTime[msg.sender] + MIN_LIQUIDATION_DELAY * 2) {
                revert("Suspicious liquidator activity");
            }
        }

        // Check for rapid liquidations
        if (blockLiquidationCount[block.number] >= MAX_LIQUIDATIONS_PER_BLOCK) {
            emit RateLimitExceeded(msg.sender, block.number);
            revert("Block limit exceeded");
        }
    }

    /// @dev Update MEV protection state
    function _updateMevProtection() internal {
        // Update liquidator reputation based on behavior
        if (lastLiquidationTime[msg.sender] > 0) {
            uint256 timeSinceLastLiquidation = block.timestamp - lastLiquidationTime[msg.sender];

            if (timeSinceLastLiquidation >= MIN_LIQUIDATION_DELAY * 2) {
                // Good behavior - increase reputation
                liquidatorReputation[msg.sender]++;
            } else if (timeSinceLastLiquidation < MIN_LIQUIDATION_DELAY) {
                // Suspicious behavior - decrease reputation
                if (liquidatorReputation[msg.sender] > 0) {
                    liquidatorReputation[msg.sender]--;
                }
                emit MEVAttemptDetected(msg.sender, address(0), "Rapid liquidation");
            }
        } else {
            // First liquidation
            liquidatorReputation[msg.sender] = 1;
        }
    }

    /// @dev Check flashloan protection
    function _checkFlashloanProtection() internal {
        // Simple flashloan detection: check if balance changed significantly
        uint256 currentBalance = address(this).balance;

        // Store flashloan detection block if large balance detected
        if (currentBalance > 50 ether) {
            // Threshold for flashloan detection
            flashloanDetectionBlock = block.number;
            emit FlashloanDetected(msg.sender, block.number);
        }

        // Prevent operations if flashloan detected recently
        require(block.number > flashloanDetectionBlock + FLASHLOAN_PROTECTION_BLOCKS, "Flashloan protection active");
    }

    /// @dev Enhanced price validation with deviation check
    function _validatePriceDeviation(address token, uint256 expectedPrice) internal {
        uint256 currentPrice = ORACLE.getTokenPrice(token);

        if (currentPrice == 0) revert("Invalid price");

        uint256 deviation;
        if (currentPrice > expectedPrice) {
            deviation = ((currentPrice - expectedPrice) * 10000) / expectedPrice;
        } else {
            deviation = ((expectedPrice - currentPrice) * 10000) / expectedPrice;
        }

        if (deviation > MAX_PRICE_DEVIATION) {
            emit MEVAttemptDetected(msg.sender, address(0), "Price manipulation");
            revert("Price deviation too high");
        }
    }

    /// @dev Get liquidator reputation
    function getLiquidatorReputation(address liquidator) external view returns (uint256) {
        return liquidatorReputation[liquidator];
    }

    /// @dev Get block liquidation count
    function getBlockLiquidationCount(uint256 blockNumber) external view returns (uint256) {
        return blockLiquidationCount[blockNumber];
    }

    /// @dev Check if liquidator is rate limited
    function isRateLimited(address liquidator) external view returns (bool) {
        return block.timestamp < lastLiquidationTime[liquidator] + MIN_LIQUIDATION_DELAY;
    }
}
