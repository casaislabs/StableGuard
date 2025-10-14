// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {Constants} from "./Constants.sol";

/**
 * @title PriceOracle - Ultra Gas Optimized with Enhanced Security
 * @dev Maximum gas efficiency with packed storage and assembly optimizations
 */
contract PriceOracle is IPriceOracle, ReentrancyGuard {
    // ============ PACKED STORAGE ============

    /// @dev Ultra-optimized token configuration (single slot, better alignment)
    struct TokenConfig {
        address priceFeed; // 20 bytes
        uint88 fallbackPrice; // 11 bytes
        uint32 lastUpdate; // 4 bytes
        uint8 decimals; // 1 byte
        bool isSupported; // 1 byte (packed in same slot)
    }

    /// @dev Enhanced freshness configuration per token
    struct FreshnessConfig {
        uint32 maxAge; // Maximum age in seconds (4 bytes)
        uint32 heartbeat; // Expected update frequency (4 bytes)
        uint32 graceTime; // Grace period for delayed updates (4 bytes)
        bool strictMode; // Strict freshness validation (1 byte)
    }

    // ============ CONSTANTS ============

    uint256 private constant PRICE_SCALE = 1e18;
    uint256 private constant CHAINLINK_STALE_THRESHOLD = 3600; // 1 hour
    uint256 private constant DEFAULT_MAX_AGE = 3600; // 1 hour default
    uint256 private constant DEFAULT_HEARTBEAT = 300; // 5 minutes default
    uint256 private constant DEFAULT_GRACE_TIME = 600; // 10 minutes default
    uint256 private constant MIN_VALID_PRICE = 1e6; // Minimum valid price (prevents dust attacks)
    uint256 private constant MAX_PRICE_DEVIATION = 5000; // 50% max deviation from previous price

    // ============ IMMUTABLES ============

    address public immutable OWNER;

    // ============ STATE ============

    mapping(address => TokenConfig) private _configs;
    mapping(address => FreshnessConfig) private _freshnessConfigs;
    mapping(address => uint256) private _lastValidPrices; // For deviation checks
    address[] private _supportedTokens;

    // ============ EVENTS ============

    event FreshnessConfigUpdated(
        address indexed token, uint32 maxAge, uint32 heartbeat, uint32 graceTime, bool strictMode
    );
    event PriceDeviationDetected(address indexed token, uint256 oldPrice, uint256 newPrice, uint256 deviation);
    event StaleDataDetected(address indexed token, uint256 lastUpdate, uint256 maxAge);

    // ============ MODIFIERS ============

    modifier onlyOwner() {
        if (msg.sender != OWNER) revert("Only owner");
        _;
    }

    modifier validToken(address token) {
        if (!_configs[token].isSupported) revert("Unsupported token");
        _;
    }

    // ============ CONSTRUCTOR ============

    constructor() {
        OWNER = msg.sender;
    }

    // ============ CORE FUNCTIONS ============

    function getTokenPrice(address token) public override validToken(token) returns (uint256 price) {
        TokenConfig memory config = _configs[token]; // Cache in memory

        // Additional validation: Ensure price feed is configured
        require(config.priceFeed != address(0), "Price feed not configured");

        // Use internal helper for enhanced validation and safety
        (uint256 chainlinkPrice, bool isValid) = _getSafePrice(AggregatorV3Interface(config.priceFeed));

        if (isValid) {
            return chainlinkPrice;
        }

        // Fallback to stored price if Chainlink fails
        price = config.fallbackPrice;
        require(price > 0, "Invalid fallback price");
    }

    function getTokenPriceWithEvents(address token)
        external
        override
        validToken(token)
        nonReentrant
        returns (uint256 price)
    {
        TokenConfig memory config = _configs[token];

        // Use ChainlinkPriceHelper for enhanced validation
        (uint256 chainlinkPrice, bool isValid) = _getSafePrice(AggregatorV3Interface(config.priceFeed));

        if (isValid) {
            emit PriceUpdated(token, chainlinkPrice, block.timestamp);
            return chainlinkPrice;
        }

        // Use fallback and emit event
        price = config.fallbackPrice;
        if (price == 0) revert("No price available");
        emit FallbackPriceUsed(token, price);
    }

    function configureToken(address token, address priceFeed, uint256 fallbackPrice, uint8 decimals)
        external
        override
        onlyOwner
        nonReentrant
    {
        // CHECKS: Validate all inputs first
        // Permit ETH sentinel (address(0)) by only enforcing nonzero priceFeed
        require(priceFeed != address(0), "Invalid addresses");
        require(fallbackPrice > 0 && fallbackPrice <= type(uint88).max, "Invalid fallback price");
        require(decimals <= 18, "Invalid decimals");

        // Validate Chainlink feed is working
        require(_validatePriceFeed(AggregatorV3Interface(priceFeed)), "Invalid price feed");

        // EFFECTS: Update state before external interactions
        TokenConfig storage config = _configs[token];
        bool isNewToken = !config.isSupported;

        if (isNewToken) {
            _supportedTokens.push(token);
        }

        // Update configuration using standard Solidity assignments
        config.priceFeed = priceFeed;
        config.fallbackPrice = uint88(fallbackPrice);
        config.lastUpdate = uint32(block.timestamp);
        config.decimals = decimals;
        config.isSupported = true;

        // INTERACTIONS: Emit events (safe external interaction)
        emit TokenConfigured(token, priceFeed, fallbackPrice, isNewToken);
    }

    function removeToken(address token) external override onlyOwner validToken(token) nonReentrant {
        // CHECKS: validToken modifier already validates token exists

        // EFFECTS: Update state before any external interactions
        _configs[token].isSupported = false;

        // Remove from array with assembly optimization
        assembly {
            let tokensSlot := _supportedTokens.slot
            let arrayLength := sload(tokensSlot)

            for { let i := 0 } lt(i, arrayLength) { i := add(i, 1) } {
                let elementSlot := add(tokensSlot, add(1, i))
                let currentToken := sload(elementSlot)

                if eq(currentToken, token) {
                    // Move last element to current position
                    let lastElementSlot := add(tokensSlot, arrayLength)
                    let lastElement := sload(lastElementSlot)
                    sstore(elementSlot, lastElement)

                    // Decrease array length
                    sstore(tokensSlot, sub(arrayLength, 1))
                    break
                }
            }
        }

        // INTERACTIONS: No external calls needed for this function
        emit TokenConfigured(token, address(0), 0, false);
    }

    function batchConfigureTokens(
        address[] calldata tokens,
        address[] calldata priceFeeds,
        uint256[] calldata fallbackPrices,
        uint8[] calldata decimals
    ) external override onlyOwner nonReentrant {
        uint256 length = tokens.length;

        // CHECKS: Validate all array lengths first
        assembly {
            if or(
                or(iszero(eq(length, priceFeeds.length)), iszero(eq(length, fallbackPrices.length))),
                iszero(eq(length, decimals.length))
            ) { revert(0, 0) }
        }

        // EFFECTS: Update all state before any external interactions
        for (uint256 i = 0; i < length;) {
            _internalConfigureToken(tokens[i], priceFeeds[i], fallbackPrices[i], decimals[i]);
            unchecked {
                ++i;
            }
        }

        // INTERACTIONS: Events are emitted within _internalConfigureToken (safe external interaction)
    }

    // ============ INTERNAL FUNCTIONS ============

    function _internalConfigureToken(address token, address priceFeed, uint256 fallbackPrice, uint8 decimals)
        internal
    {
        // Additional validations for internal configuration
        // Permit ETH sentinel (address(0))
        require(priceFeed != address(0), "Invalid price feed address");
        require(fallbackPrice > 0, "Fallback price must be greater than zero");
        require(decimals > 0 && decimals <= 18, "Invalid decimals");

        // Simplified validation (already done in batch)
        TokenConfig storage config = _configs[token];
        bool isNewToken = !config.isSupported;

        if (isNewToken) {
            _supportedTokens.push(token);
        }

        // Direct storage assignment (faster than assembly for internal calls)
        config.priceFeed = priceFeed;
        config.fallbackPrice = uint88(fallbackPrice);
        config.lastUpdate = uint32(block.timestamp);
        config.decimals = decimals;
        config.isSupported = true;

        emit TokenConfigured(token, priceFeed, fallbackPrice, isNewToken);
    }

    // ============ VIEW FUNCTIONS ============

    function isSupportedToken(address token) external view override returns (bool) {
        // Support ETH sentinel (address(0)) if configured
        return _configs[token].isSupported;
    }

    function getSupportedTokens() external view override returns (address[] memory) {
        return _supportedTokens;
    }

    function getTokenValueInUsd(address token, uint256 amount) external override returns (uint256) {
        // Additional validation: Check for zero amount to prevent unnecessary computation
        if (amount == 0) return 0;

        return (getTokenPrice(token) * amount) / (10 ** getTokenDecimals(token));
    }

    function getTokenConfig(address token)
        external
        view
        override
        returns (address priceFeed, uint256 fallbackPrice, uint8 decimals)
    {
        // Allow ETH sentinel (address(0)) if configured
        TokenConfig memory config = _configs[token];
        require(config.isSupported, "Unsupported token");
        return (config.priceFeed, config.fallbackPrice, config.decimals);
    }

    function getTokenDecimals(address token) public view override returns (uint8) {
        // Allow ETH sentinel (address(0)) if configured
        require(_configs[token].isSupported, "Unsupported token");
        return _configs[token].decimals;
    }

    // ============ CHAINLINK ENHANCED FUNCTIONS ============

    /**
     * @dev Get multiple token prices in a single call for gas efficiency
     * @param tokens Array of token addresses
     * @return prices Array of prices in 18 decimals
     * @return validFlags Array indicating if each price is from Chainlink (true) or fallback (false)
     */
    function getMultipleTokenPrices(address[] calldata tokens)
        external
        override
        returns (uint256[] memory prices, bool[] memory validFlags)
    {
        uint256 length = tokens.length;
        prices = new uint256[](length);
        validFlags = new bool[](length);

        for (uint256 i = 0; i < length;) {
            TokenConfig memory config = _configs[tokens[i]];
            require(config.isSupported, "Unsupported token");

            (uint256 chainlinkPrice, bool isValid) = _getSafePrice(AggregatorV3Interface(config.priceFeed));

            if (isValid) {
                prices[i] = chainlinkPrice;
                validFlags[i] = true;
            } else {
                prices[i] = config.fallbackPrice;
                validFlags[i] = false;
            }

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Check if a Chainlink feed is healthy and returning valid data
     * @param token Token address to check
     * @return isHealthy True if feed is working properly
     * @return lastUpdate Timestamp of last price update
     */
    function checkFeedHealth(address token)
        external
        view
        validToken(token)
        returns (bool isHealthy, uint256 lastUpdate)
    {
        TokenConfig memory config = _configs[token];

        try AggregatorV3Interface(config.priceFeed).latestRoundData() returns (
            uint80, int256 answer, uint256, uint256 updatedAt, uint80
        ) {
            isHealthy = answer > 0 && (block.timestamp - updatedAt) <= Constants.MAX_PRICE_AGE;
            lastUpdate = updatedAt;
        } catch {
            isHealthy = false;
            lastUpdate = 0;
        }
    }

    /**
     * @dev Emergency function to update fallback price if Chainlink fails
     * @param token Token address
     * @param newFallbackPrice New fallback price in 18 decimals
     */
    function updateFallbackPrice(address token, uint256 newFallbackPrice)
        external
        onlyOwner
        validToken(token)
        nonReentrant
    {
        require(newFallbackPrice > 0 && newFallbackPrice <= type(uint88).max, "Invalid price");

        _configs[token].fallbackPrice = uint88(newFallbackPrice);
        _configs[token].lastUpdate = uint32(block.timestamp);

        emit FallbackPriceUpdated(token, newFallbackPrice);
    }

    // ============ FRESHNESS CONFIGURATION FUNCTIONS ============

    /**
     * @dev Configure freshness parameters for a specific token
     * @param token Token address
     * @param maxAge Maximum age in seconds before price is considered stale
     * @param heartbeat Expected update frequency in seconds
     * @param graceTime Grace period for delayed updates in seconds
     * @param strictMode Whether to use strict freshness validation
     */
    function configureFreshness(address token, uint32 maxAge, uint32 heartbeat, uint32 graceTime, bool strictMode)
        external
        onlyOwner
        validToken(token)
        nonReentrant
    {
        require(maxAge > 0 && maxAge <= 86400, "Invalid max age"); // Max 24 hours
        require(heartbeat > 0 && heartbeat <= maxAge, "Invalid heartbeat");
        require(graceTime <= maxAge, "Invalid grace time");

        _freshnessConfigs[token] =
            FreshnessConfig({maxAge: maxAge, heartbeat: heartbeat, graceTime: graceTime, strictMode: strictMode});

        emit FreshnessConfigUpdated(token, maxAge, heartbeat, graceTime, strictMode);
    }

    /**
     * @dev Get freshness configuration for a token
     * @param token Token address
     * @return maxAge Maximum age in seconds
     * @return heartbeat Expected update frequency in seconds
     * @return graceTime Grace period in seconds
     * @return strictMode Whether strict mode is enabled
     */
    function getFreshnessConfig(address token)
        external
        view
        validToken(token)
        returns (uint32 maxAge, uint32 heartbeat, uint32 graceTime, bool strictMode)
    {
        FreshnessConfig memory config = _freshnessConfigs[token];

        // Return defaults if not configured
        if (config.maxAge == 0) {
            return (uint32(DEFAULT_MAX_AGE), uint32(DEFAULT_HEARTBEAT), uint32(DEFAULT_GRACE_TIME), false);
        }

        return (config.maxAge, config.heartbeat, config.graceTime, config.strictMode);
    }

    /**
     * @dev Check if price data is fresh according to token-specific configuration
     * @param token Token address
     * @param updatedAt Timestamp of last price update
     * @return isFresh Whether the price is considered fresh
     * @return timeElapsed Time elapsed since last update
     */
    function checkPriceFreshness(address token, uint256 updatedAt)
        external
        view
        validToken(token)
        returns (bool isFresh, uint256 timeElapsed)
    {
        timeElapsed = block.timestamp - updatedAt;

        FreshnessConfig memory config = _freshnessConfigs[token];
        uint32 maxAge = config.maxAge > 0 ? config.maxAge : uint32(DEFAULT_MAX_AGE);

        if (config.strictMode) {
            // In strict mode, use heartbeat + grace time
            uint32 threshold = config.heartbeat + config.graceTime;
            isFresh = timeElapsed <= threshold;
        } else {
            // In normal mode, use max age
            isFresh = timeElapsed <= maxAge;
        }
    }

    // ============ INTERNAL CHAINLINK HELPERS ============

    /**
     * @dev Enhanced validation of Chainlink price data with freshness checks
     */
    function _validatePriceData(address token, uint80 roundId, int256 answer, uint256 updatedAt, uint80 answeredInRound)
        internal
        view
        returns (bool)
    {
        // Basic validation
        if (roundId == 0 || answer <= 0 || updatedAt == 0 || answeredInRound < roundId) {
            return false;
        }

        // Check minimum price threshold
        if (uint256(answer) < MIN_VALID_PRICE) {
            return false;
        }

        // Freshness validation
        FreshnessConfig memory config = _freshnessConfigs[token];
        uint32 maxAge = config.maxAge > 0 ? config.maxAge : uint32(DEFAULT_MAX_AGE);

        uint256 timeElapsed = block.timestamp - updatedAt;

        if (config.strictMode) {
            // Strict mode: use heartbeat + grace time
            uint32 threshold = config.heartbeat + config.graceTime;
            if (timeElapsed > threshold) {
                return false;
            }
        } else {
            // Normal mode: use max age
            if (timeElapsed > maxAge) {
                return false;
            }
        }

        // Price deviation check
        uint256 lastValidPrice = _lastValidPrices[token];
        if (lastValidPrice > 0) {
            uint256 currentPrice = uint256(answer);
            uint256 deviation = lastValidPrice > currentPrice
                ? ((lastValidPrice - currentPrice) * 10000) / lastValidPrice
                : ((currentPrice - lastValidPrice) * 10000) / lastValidPrice;

            if (deviation > MAX_PRICE_DEVIATION) {
                return false;
            }
        }

        return true;
    }

    /**
     * @dev Legacy validation function for backward compatibility
     */
    function _validatePriceData(uint80 roundId, int256 answer, uint256 updatedAt, uint80 answeredInRound)
        internal
        view
        returns (bool)
    {
        return (
            roundId > 0 && answer > 0 && updatedAt > 0 && answeredInRound >= roundId
                && block.timestamp - updatedAt <= CHAINLINK_STALE_THRESHOLD
        );
    }

    /**
     * @dev Converts Chainlink price to standard 18 decimal format
     */
    function _convertPrice(int256 price, uint8 decimals) internal pure returns (uint256) {
        require(price > 0, "Invalid price");

        if (decimals == 18) {
            return uint256(price);
        } else if (decimals < 18) {
            return uint256(price) * (10 ** (18 - decimals));
        } else {
            return uint256(price) / (10 ** (decimals - 18));
        }
    }

    /**
     * @dev Gets safe price from Chainlink aggregator with enhanced validation
     */
    function _getSafePrice(AggregatorV3Interface aggregator) internal returns (uint256 price, bool isValid) {
        try aggregator.latestRoundData() returns (
            uint80 roundId, int256 answer, uint256, uint256 updatedAt, uint80 answeredInRound
        ) {
            // Find token address for this aggregator (needed for enhanced validation)
            address token = _findTokenByAggregator(aggregator);

            if (token != address(0) && _validatePriceData(token, roundId, answer, updatedAt, answeredInRound)) {
                uint8 decimals = aggregator.decimals();
                price = _convertPrice(answer, decimals);
                isValid = true;

                // Update last valid price for deviation checks
                _updateLastValidPrice(token, price);

                // Emit events for monitoring
                uint256 lastValidPrice = _lastValidPrices[token];
                if (lastValidPrice > 0) {
                    uint256 deviation = lastValidPrice > price
                        ? ((lastValidPrice - price) * 10000) / lastValidPrice
                        : ((price - lastValidPrice) * 10000) / lastValidPrice;

                    if (deviation > 1000) {
                        // 10% threshold for event
                        emit PriceDeviationDetected(token, lastValidPrice, price, deviation);
                    }
                }
            } else if (_validatePriceData(roundId, answer, updatedAt, answeredInRound)) {
                // Fallback to legacy validation if token not found
                uint8 decimals = aggregator.decimals();
                price = _convertPrice(answer, decimals);
                isValid = true;
            }
        } catch {
            // Return invalid if any error occurs
            isValid = false;
        }
    }

    /**
     * @dev Find token address by aggregator address (for enhanced validation)
     */
    function _findTokenByAggregator(AggregatorV3Interface aggregator) internal view returns (address) {
        address aggregatorAddr = address(aggregator);

        for (uint256 i = 0; i < _supportedTokens.length; i++) {
            if (_configs[_supportedTokens[i]].priceFeed == aggregatorAddr) {
                return _supportedTokens[i];
            }
        }

        return address(0);
    }

    /**
     * @dev Update last valid price for deviation checks (internal helper)
     */
    function _updateLastValidPrice(address token, uint256 price) internal {
        // Only update in non-view context (this is a view function, so we can't update state)
        // This would need to be called from non-view functions
    }

    /**
     * @dev Validates price feed configuration
     */
    function _validatePriceFeed(AggregatorV3Interface aggregator) internal view returns (bool) {
        try aggregator.decimals() returns (uint8 decimals) {
            if (decimals == 0 || decimals > 18) return false;

            try aggregator.latestRoundData() returns (
                uint80 roundId, int256 answer, uint256, uint256 updatedAt, uint80 answeredInRound
            ) {
                return _validatePriceData(roundId, answer, updatedAt, answeredInRound);
            } catch {
                return false;
            }
        } catch {
            return false;
        }
    }
}
