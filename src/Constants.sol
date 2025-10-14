// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Constants
 * @dev Centralized constants for mainnet addresses to ensure consistency across all contracts
 */
library Constants {
    // ============ MAINNET TOKEN ADDRESSES ============

    // Native ETH
    address internal constant ETH_TOKEN = address(0);

    // Major tokens
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // DeFi tokens
    address internal constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address internal constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address internal constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address internal constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address internal constant MKR = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;

    // ============ CHAINLINK PRICE FEED ADDRESSES ============

    address internal constant ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address internal constant WBTC_USD_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address internal constant USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address internal constant USDT_USD_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
    address internal constant DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address internal constant LINK_USD_FEED = 0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c;
    address internal constant UNI_USD_FEED = 0x553303d460EE0afB37EdFf9bE42922D8FF63220e;
    address internal constant AAVE_USD_FEED = 0x547a514d5e3769680Ce22B2361c10Ea13619e8a9;
    address internal constant COMP_USD_FEED = 0xdbd020CAeF83eFd542f4De03e3cF0C28A4428bd5;
    address internal constant MKR_USD_FEED = 0xec1D1B3b0443256cc3860e24a46F108e699484Aa;

    // ============ DEX ADDRESSES (UNISWAP V2 ONLY) ============

    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    // ============ TOKEN DECIMALS ============

    uint8 internal constant ETH_DECIMALS = 18;
    uint8 internal constant WETH_DECIMALS = 18;
    uint8 internal constant WBTC_DECIMALS = 8;
    uint8 internal constant USDC_DECIMALS = 6;
    uint8 internal constant USDT_DECIMALS = 6;
    uint8 internal constant DAI_DECIMALS = 18;
    uint8 internal constant LINK_DECIMALS = 18;
    uint8 internal constant UNI_DECIMALS = 18;
    uint8 internal constant AAVE_DECIMALS = 18;
    uint8 internal constant COMP_DECIMALS = 18;
    uint8 internal constant MKR_DECIMALS = 18;

    // ============ FALLBACK PRICES (in 18 decimals) ============

    uint256 internal constant ETH_FALLBACK_PRICE = 2000e18; // $2,000
    uint256 internal constant WBTC_FALLBACK_PRICE = 45000e18; // $45,000
    uint256 internal constant USDC_FALLBACK_PRICE = 1e18; // $1.00
    uint256 internal constant USDT_FALLBACK_PRICE = 1e18; // $1.00
    uint256 internal constant DAI_FALLBACK_PRICE = 1e18; // $1.00
    uint256 internal constant LINK_FALLBACK_PRICE = 15e18; // $15
    uint256 internal constant UNI_FALLBACK_PRICE = 8e18; // $8
    uint256 internal constant AAVE_FALLBACK_PRICE = 100e18; // $100
    uint256 internal constant COMP_FALLBACK_PRICE = 50e18; // $50
    uint256 internal constant MKR_FALLBACK_PRICE = 1500e18; // $1,500

    // ============ COLLATERAL CONFIGURATION ============

    // LTV (Loan-to-Value) ratios in basis points
    uint256 internal constant ETH_LTV = 8000; // 80%
    uint256 internal constant WBTC_LTV = 7500; // 75%
    uint256 internal constant USDC_LTV = 9500; // 95%
    uint256 internal constant USDT_LTV = 9500; // 95%
    uint256 internal constant DAI_LTV = 9500; // 95%
    uint256 internal constant LINK_LTV = 7000; // 70%
    uint256 internal constant UNI_LTV = 6500; // 65%
    uint256 internal constant AAVE_LTV = 7000; // 70%
    uint256 internal constant COMP_LTV = 6500; // 65%
    uint256 internal constant MKR_LTV = 7000; // 70%

    // Liquidation thresholds in basis points
    uint256 internal constant ETH_LIQUIDATION_THRESHOLD = 12000; // 120%
    uint256 internal constant WBTC_LIQUIDATION_THRESHOLD = 13000; // 130%
    uint256 internal constant USDC_LIQUIDATION_THRESHOLD = 10500; // 105%
    uint256 internal constant USDT_LIQUIDATION_THRESHOLD = 10500; // 105%
    uint256 internal constant DAI_LIQUIDATION_THRESHOLD = 10500; // 105%
    uint256 internal constant LINK_LIQUIDATION_THRESHOLD = 14000; // 140%
    uint256 internal constant UNI_LIQUIDATION_THRESHOLD = 15000; // 150%
    uint256 internal constant AAVE_LIQUIDATION_THRESHOLD = 14000; // 140%
    uint256 internal constant COMP_LIQUIDATION_THRESHOLD = 15000; // 150%
    uint256 internal constant MKR_LIQUIDATION_THRESHOLD = 14000; // 140%

    // Liquidation penalties in basis points
    uint256 internal constant ETH_LIQUIDATION_PENALTY = 500; // 5%
    uint256 internal constant WBTC_LIQUIDATION_PENALTY = 800; // 8%
    uint256 internal constant USDC_LIQUIDATION_PENALTY = 200; // 2%
    uint256 internal constant USDT_LIQUIDATION_PENALTY = 200; // 2%
    uint256 internal constant DAI_LIQUIDATION_PENALTY = 200; // 2%
    uint256 internal constant LINK_LIQUIDATION_PENALTY = 1000; // 10%
    uint256 internal constant UNI_LIQUIDATION_PENALTY = 1200; // 12%
    uint256 internal constant AAVE_LIQUIDATION_PENALTY = 1000; // 10%
    uint256 internal constant COMP_LIQUIDATION_PENALTY = 1200; // 12%
    uint256 internal constant MKR_LIQUIDATION_PENALTY = 1000; // 10%

    // ============ SYSTEM CONFIGURATION ============

    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant PRICE_PRECISION = 1e18;
    uint256 public constant MAX_PRICE_AGE = 86400; // 24 hours

    // Arbitrage configuration
    uint256 public constant MIN_ARBITRAGE_PROFIT = 50; // 0.5%
    uint256 public constant MAX_ARBITRAGE_SLIPPAGE = 300; // 3%
    uint256 public constant ARBITRAGE_COOLDOWN = 60; // 1 minute

    // Repeg configuration
    uint256 public constant REPEG_DEVIATION_THRESHOLD = 500; // 5%
    uint256 public constant REPEG_COOLDOWN = 3600; // 1 hour
    uint256 public constant REPEG_ARBITRAGE_WINDOW = 1800; // 30 minutes
    uint256 public constant REPEG_INCENTIVE_RATE = 100; // 1%
    uint256 public constant MAX_REPEG_PER_DAY = 10;

    // ============ HELPER FUNCTIONS ============

    /**
     * @dev Get token configuration by address
     */
    function getTokenConfig(address token)
        internal
        pure
        returns (
            address priceFeed,
            uint256 fallbackPrice,
            uint8 decimals,
            uint256 ltv,
            uint256 liquidationThreshold,
            uint256 liquidationPenalty
        )
    {
        if (token == ETH_TOKEN) {
            return (
                ETH_USD_FEED,
                ETH_FALLBACK_PRICE,
                ETH_DECIMALS,
                ETH_LTV,
                ETH_LIQUIDATION_THRESHOLD,
                ETH_LIQUIDATION_PENALTY
            );
        } else if (token == WETH) {
            return (
                ETH_USD_FEED,
                ETH_FALLBACK_PRICE,
                WETH_DECIMALS,
                ETH_LTV,
                ETH_LIQUIDATION_THRESHOLD,
                ETH_LIQUIDATION_PENALTY
            );
        } else if (token == WBTC) {
            return (
                WBTC_USD_FEED,
                WBTC_FALLBACK_PRICE,
                WBTC_DECIMALS,
                WBTC_LTV,
                WBTC_LIQUIDATION_THRESHOLD,
                WBTC_LIQUIDATION_PENALTY
            );
        } else if (token == USDC) {
            return (
                USDC_USD_FEED,
                USDC_FALLBACK_PRICE,
                USDC_DECIMALS,
                USDC_LTV,
                USDC_LIQUIDATION_THRESHOLD,
                USDC_LIQUIDATION_PENALTY
            );
        } else if (token == USDT) {
            return (
                USDT_USD_FEED,
                USDT_FALLBACK_PRICE,
                USDT_DECIMALS,
                USDT_LTV,
                USDT_LIQUIDATION_THRESHOLD,
                USDT_LIQUIDATION_PENALTY
            );
        } else if (token == DAI) {
            return (
                DAI_USD_FEED,
                DAI_FALLBACK_PRICE,
                DAI_DECIMALS,
                DAI_LTV,
                DAI_LIQUIDATION_THRESHOLD,
                DAI_LIQUIDATION_PENALTY
            );
        } else if (token == LINK) {
            return (
                LINK_USD_FEED,
                LINK_FALLBACK_PRICE,
                LINK_DECIMALS,
                LINK_LTV,
                LINK_LIQUIDATION_THRESHOLD,
                LINK_LIQUIDATION_PENALTY
            );
        } else if (token == UNI) {
            return (
                UNI_USD_FEED,
                UNI_FALLBACK_PRICE,
                UNI_DECIMALS,
                UNI_LTV,
                UNI_LIQUIDATION_THRESHOLD,
                UNI_LIQUIDATION_PENALTY
            );
        } else if (token == AAVE) {
            return (
                AAVE_USD_FEED,
                AAVE_FALLBACK_PRICE,
                AAVE_DECIMALS,
                AAVE_LTV,
                AAVE_LIQUIDATION_THRESHOLD,
                AAVE_LIQUIDATION_PENALTY
            );
        } else if (token == COMP) {
            return (
                COMP_USD_FEED,
                COMP_FALLBACK_PRICE,
                COMP_DECIMALS,
                COMP_LTV,
                COMP_LIQUIDATION_THRESHOLD,
                COMP_LIQUIDATION_PENALTY
            );
        } else if (token == MKR) {
            return (
                MKR_USD_FEED,
                MKR_FALLBACK_PRICE,
                MKR_DECIMALS,
                MKR_LTV,
                MKR_LIQUIDATION_THRESHOLD,
                MKR_LIQUIDATION_PENALTY
            );
        } else {
            revert("Unsupported token");
        }
    }

    /**
     * @dev Check if token is supported
     */
    function isSupportedToken(address token) internal pure returns (bool) {
        return token == ETH_TOKEN || token == WETH || token == WBTC || token == USDC || token == USDT || token == DAI
            || token == LINK || token == UNI || token == AAVE || token == COMP || token == MKR;
    }
}
