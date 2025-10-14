// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {LiquidationManager} from "../src/LiquidationManager.sol";
import {ILiquidationManager} from "../src/interfaces/ILiquidationManager.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {ICollateralManager} from "../src/interfaces/ICollateralManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title LiquidationManager Test Suite
/// @dev Comprehensive tests for LiquidationManager contract
contract LiquidationManagerTest is Test {
    // ============ CONTRACTS ============
    LiquidationManager public liquidationManager;
    MockPriceOracle public mockOracle;
    MockCollateralManager public mockCollateral;
    MockERC20 public mockToken;
    MockStableGuard public mockStableGuard;

    // ============ TEST ACCOUNTS ============
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public liquidator = makeAddr("liquidator");
    address public attacker = makeAddr("attacker");

    // ============ TEST CONSTANTS ============
    uint256 public constant INITIAL_BALANCE = 1000 ether;
    uint256 public constant TOKEN_PRICE = 2000e18; // $2000 per token
    uint256 public constant DEBT_AMOUNT = 1000e18; // $1000 debt
    uint256 public constant COLLATERAL_AMOUNT = 1e18; // 1 token

    // ============ EVENTS ============
    event LiquidationEvent(
        address indexed liquidator,
        address indexed user,
        address indexed token,
        uint256 debtAmount,
        uint256 liquidationAmount
    );

    event MEVAttemptDetected(address indexed liquidator, address indexed user, string reason);
    event FlashloanDetected(address indexed liquidator, uint256 blockNumber);
    event RateLimitExceeded(address indexed liquidator, uint256 blockNumber);

    // ============ SETUP ============
    function setUp() public {
        // Deploy mock contracts
        mockOracle = new MockPriceOracle();
        mockCollateral = new MockCollateralManager();
        mockToken = new MockERC20("Test Token", "TEST");
        mockStableGuard = new MockStableGuard();

        // Deploy LiquidationManager
        vm.prank(owner);
        liquidationManager = new LiquidationManager(owner, address(mockOracle), address(mockCollateral));

        // Set up initial state
        vm.prank(owner);
        liquidationManager.setStableGuard(address(mockStableGuard));

        // Fund accounts
        vm.deal(liquidator, INITIAL_BALANCE);
        vm.deal(user, INITIAL_BALANCE);
        vm.deal(attacker, INITIAL_BALANCE);

        // Set up mock data
        mockOracle.setTokenPrice(address(mockToken), TOKEN_PRICE);
        mockOracle.setTokenDecimals(address(mockToken), 18);
        mockOracle.addSupportedToken(address(mockToken));

        mockCollateral.setUserCollateral(user, address(mockToken), COLLATERAL_AMOUNT);
        mockCollateral.setTotalCollateralValue(user, TOKEN_PRICE); // $2000 collateral

        // Set up user debt
        mockStableGuard.setUserDebt(user, DEBT_AMOUNT); // $1000 debt

        // Mint tokens to liquidation manager for transfers
        mockToken.mint(address(liquidationManager), 10 ether);

        // Advance time and blocks to bypass MEV protection
        vm.warp(block.timestamp + 100); // Advance time by 100 seconds
        vm.roll(block.number + 10); // Advance blocks to bypass flashloan protection
    }

    // ============ BASIC FUNCTIONALITY TESTS ============

    function test_Constructor() public {
        // Test valid constructor
        LiquidationManager newManager = new LiquidationManager(owner, address(mockOracle), address(mockCollateral));

        (address stableGuard, uint64 minRatio, uint32 liqThreshold, uint32 bonus) = newManager.getConfig();

        assertEq(stableGuard, address(0));
        assertEq(minRatio, 15000); // 150%
        assertEq(liqThreshold, 12000); // 120%
        assertEq(bonus, 1000); // 10%
    }

    function test_Constructor_RevertZeroAddresses() public {
        // Test zero owner
        vm.expectRevert();
        new LiquidationManager(address(0), address(mockOracle), address(mockCollateral));

        // Test zero oracle
        vm.expectRevert();
        new LiquidationManager(owner, address(0), address(mockCollateral));

        // Test zero collateral
        vm.expectRevert();
        new LiquidationManager(owner, address(mockOracle), address(0));
    }

    function test_SetStableGuard() public {
        address newGuard = makeAddr("newGuard");

        vm.prank(owner);
        liquidationManager.setStableGuard(newGuard);

        (address stableGuard,,,) = liquidationManager.getConfig();
        assertEq(stableGuard, newGuard);
    }

    function test_SetStableGuard_RevertUnauthorized() public {
        vm.prank(user);
        vm.expectRevert();
        liquidationManager.setStableGuard(makeAddr("newGuard"));
    }

    function test_SetStableGuard_RevertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert();
        liquidationManager.setStableGuard(address(0));
    }

    // ============ LIQUIDATION TESTS ============

    function test_Liquidate_Success() public {
        // Make position liquidatable
        mockCollateral.setTotalCollateralValue(user, 1100e18); // $1100 collateral, $1000 debt = 110% ratio

        vm.prank(address(mockStableGuard));
        vm.expectEmit(true, true, true, false);
        emit LiquidationEvent(address(mockStableGuard), user, address(mockToken), DEBT_AMOUNT, 0);

        bool success = liquidationManager.liquidate(user, DEBT_AMOUNT);
        assertTrue(success);
    }

    function test_Liquidate_WithSpecificToken() public {
        // Make position liquidatable
        mockCollateral.setTotalCollateralValue(user, 1100e18);

        vm.prank(address(mockStableGuard));
        bool success = liquidationManager.liquidate(user, address(mockToken), DEBT_AMOUNT);
        assertTrue(success);
    }

    function test_Liquidate_RevertUnauthorized() public {
        vm.prank(liquidator);
        vm.expectRevert();
        liquidationManager.liquidate(user, DEBT_AMOUNT);
    }

    function test_Liquidate_RevertZeroDebt() public {
        vm.prank(address(mockStableGuard));
        vm.expectRevert();
        liquidationManager.liquidate(user, 0);
    }

    function test_Liquidate_RevertZeroToken() public {
        vm.prank(address(mockStableGuard));
        vm.expectRevert();
        liquidationManager.liquidate(user, address(0), DEBT_AMOUNT);
    }

    function test_Liquidate_RevertNoCollateral() public {
        mockCollateral.setUserCollateral(user, address(mockToken), 0);

        vm.prank(address(mockStableGuard));
        vm.expectRevert(ILiquidationManager.NoCollateral.selector);
        liquidationManager.liquidate(user, address(mockToken), DEBT_AMOUNT);
    }

    function test_LiquidateDirect_Owner() public {
        mockCollateral.setTotalCollateralValue(user, 1100e18);

        vm.prank(owner);
        bool success = liquidationManager.liquidateDirect(user, DEBT_AMOUNT);
        assertTrue(success);
    }

    function test_LiquidateDirect_WithToken() public {
        mockCollateral.setTotalCollateralValue(user, 1100e18);

        vm.prank(owner);
        bool success = liquidationManager.liquidateDirect(user, address(mockToken), DEBT_AMOUNT);
        assertTrue(success);
    }

    function test_LiquidateDirect_RevertUnauthorized() public {
        vm.prank(liquidator);
        vm.expectRevert();
        liquidationManager.liquidateDirect(user, DEBT_AMOUNT);
    }

    // ============ VIEW FUNCTION TESTS ============

    function test_IsLiquidatable_True() public {
        // Set collateral ratio below liquidation threshold (120%)
        mockCollateral.setTotalCollateralValue(user, 1100e18); // 110% ratio

        bool liquidatable = liquidationManager.isLiquidatable(user);
        assertTrue(liquidatable);
    }

    function test_IsLiquidatable_False() public {
        // Set collateral ratio above liquidation threshold
        mockCollateral.setTotalCollateralValue(user, 1300e18); // 130% ratio

        bool liquidatable = liquidationManager.isLiquidatable(user);
        assertFalse(liquidatable);
    }

    function test_IsLiquidatable_ZeroAddress() public {
        bool liquidatable = liquidationManager.isLiquidatable(address(0));
        assertFalse(liquidatable);
    }

    function test_IsLiquidatable_NoCollateral() public {
        mockCollateral.setTotalCollateralValue(user, 0);

        bool liquidatable = liquidationManager.isLiquidatable(user);
        assertFalse(liquidatable);
    }

    function test_GetCollateralRatio() public {
        mockCollateral.setTotalCollateralValue(user, 1500e18); // $1500 collateral

        uint256 ratio = liquidationManager.getCollateralRatio(user);
        assertEq(ratio, 15000); // 150%
    }

    function test_GetCollateralRatio_ZeroDebt() public {
        // Mock zero debt scenario
        mockCollateral.setTotalCollateralValue(user, 1500e18);
        mockStableGuard.setUserDebt(user, 0); // Set debt to zero

        // Verify mock is working
        assertEq(mockStableGuard.getDebt(user), 0);

        // Test _getDebtValue directly
        uint256 debtValue = liquidationManager.getDebtValueForTesting(user);
        assertEq(debtValue, 0, "DebtValue should be 0");

        uint256 ratio = liquidationManager.getCollateralRatio(user);
        assertEq(ratio, type(uint256).max);
    }

    function test_GetCollateralRatio_ZeroAddress() public {
        uint256 ratio = liquidationManager.getCollateralRatio(address(0));
        assertEq(ratio, 0);
    }

    function test_CalculateLiquidationAmounts() public {
        (uint256 collateralAmount, uint256 liquidationBonus) =
            liquidationManager.calculateLiquidationAmounts(user, address(mockToken), DEBT_AMOUNT);

        // Expected: (1000 * 1.1 * 1e18) / 2000e18 = 0.55e18
        uint256 expectedCollateral = (DEBT_AMOUNT * 11000 * 1e18) / (10000 * TOKEN_PRICE);
        uint256 expectedBonus = (expectedCollateral * 1000) / 10000;

        assertEq(collateralAmount, expectedCollateral);
        assertEq(liquidationBonus, expectedBonus);
    }

    function test_FindOptimalToken() public {
        address optimalToken = liquidationManager.findOptimalToken(user);
        assertEq(optimalToken, address(mockToken));
    }

    function test_FindOptimalToken_NoCollateral() public {
        mockCollateral.setUserCollateral(user, address(mockToken), 0);

        vm.expectRevert("No collateral found");
        liquidationManager.findOptimalToken(user);
    }

    function test_IsPositionSafe() public view {
        // With DEBT_AMOUNT = 1000e18, test different collateral values
        bool safe = liquidationManager.isPositionSafe(user, 1200e18, false);
        assertTrue(safe); // 120% = 120% liquidation threshold (safe)

        safe = liquidationManager.isPositionSafe(user, 1500e18, true);
        assertTrue(safe); // 150% = 150% minimum ratio (safe)

        safe = liquidationManager.isPositionSafe(user, 1100e18, false);
        assertFalse(safe); // 110% < 120% liquidation threshold (unsafe)
    }

    function test_IsPositionSafe_ZeroAddress() public view {
        bool safe = liquidationManager.isPositionSafe(address(0), 1600e18, false);
        assertFalse(safe);
    }

    function test_IsPositionSafe_ZeroCollateral() public view {
        bool safe = liquidationManager.isPositionSafe(user, 0, false);
        assertFalse(safe);
    }

    function test_IsPositionSafeByValue() public view {
        bool safe = liquidationManager.isPositionSafeByValue(1600e18, DEBT_AMOUNT);
        assertTrue(safe); // 160% > 150%

        safe = liquidationManager.isPositionSafeByValue(1400e18, DEBT_AMOUNT);
        assertFalse(safe); // 140% < 150%
    }

    function test_IsPositionSafeForLiquidation() public {
        mockCollateral.setTotalCollateralValue(user, 1300e18);

        bool safe = liquidationManager.isPositionSafeForLiquidation(user);
        assertTrue(safe); // 130% > 120%

        mockCollateral.setTotalCollateralValue(user, 1100e18);
        safe = liquidationManager.isPositionSafeForLiquidation(user);
        assertFalse(safe); // 110% < 120%
    }

    function test_IsPositionSafeForLiquidationByValue() public view {
        bool safe = liquidationManager.isPositionSafeForLiquidationByValue(1300e18, DEBT_AMOUNT);
        assertTrue(safe); // 130% > 120%

        safe = liquidationManager.isPositionSafeForLiquidationByValue(1100e18, DEBT_AMOUNT);
        assertFalse(safe); // 110% < 120%
    }

    function test_CalculateCollateralFromDebt() public view {
        uint256 result = liquidationManager.calculateCollateralFromDebt(DEBT_AMOUNT, TOKEN_PRICE);

        // Expected: (1000 * 1.2 * 1e18) / 2000e18 = 0.6e18
        uint256 expected = (DEBT_AMOUNT * 12000 * 1e18) / (10000 * TOKEN_PRICE);
        assertEq(result, expected);
    }

    function test_CalculateCollateralFromDebt_ZeroDebt() public view {
        uint256 result = liquidationManager.calculateCollateralFromDebt(0, TOKEN_PRICE);
        assertEq(result, 0);
    }

    function test_CalculateCollateralFromDebt_ZeroPrice() public {
        vm.expectRevert();
        liquidationManager.calculateCollateralFromDebt(DEBT_AMOUNT, 0);
    }

    function test_FindOptimalTokenForLiquidation() public {
        address optimalToken = liquidationManager.findOptimalTokenForLiquidation(user);
        assertEq(optimalToken, address(mockToken));
    }

    function test_FindOptimalTokenForLiquidation_ZeroAddress() public {
        address optimalToken = liquidationManager.findOptimalTokenForLiquidation(address(0));
        assertEq(optimalToken, address(0));
    }

    function test_GetLiquidationConstants() public view {
        (uint256 minRatio, uint256 liqThreshold, uint256 bonus) = liquidationManager.getLiquidationConstants();

        assertEq(minRatio, 15000); // 150%
        assertEq(liqThreshold, 12000); // 120%
        assertEq(bonus, 1000); // 10%
    }

    // ============ CONFIGURATION TESTS ============

    function test_UpdateConfig() public {
        vm.prank(owner);
        liquidationManager.updateConfig(16000, 13000, 1200); // 160%, 130%, 12%

        (, uint32 minRatio, uint32 liqThreshold, uint32 bonus) = liquidationManager.getConfig();

        assertEq(minRatio, 16000);
        assertEq(liqThreshold, 13000);
        assertEq(bonus, 1200);
    }

    function test_UpdateConfig_RevertUnauthorized() public {
        vm.prank(user);
        vm.expectRevert();
        liquidationManager.updateConfig(16000, 13000, 1200);
    }

    function test_UpdateConfig_RevertInvalidThreshold() public {
        vm.prank(owner);
        vm.expectRevert(); // liquidation threshold >= minimum ratio
        liquidationManager.updateConfig(15000, 15000, 1000);
    }

    function test_UpdateConfig_RevertExcessiveBonus() public {
        vm.prank(owner);
        vm.expectRevert(); // bonus > 20%
        liquidationManager.updateConfig(15000, 12000, 2100);
    }

    function test_UpdateConfig_RevertLowMinRatio() public {
        vm.prank(owner);
        vm.expectRevert(); // minimum ratio < 110%
        liquidationManager.updateConfig(10000, 9000, 1000);
    }

    // ============ MEV PROTECTION TESTS ============

    function test_MEVProtection_RateLimit() public {
        mockCollateral.setTotalCollateralValue(user, 1100e18);

        // First liquidation should succeed
        vm.prank(address(mockStableGuard));
        liquidationManager.liquidate(user, address(mockToken), DEBT_AMOUNT);

        // Second liquidation immediately should fail due to rate limit
        vm.prank(address(mockStableGuard));
        vm.expectRevert("Rate limited");
        liquidationManager.liquidate(user, address(mockToken), DEBT_AMOUNT);

        // After delay, should succeed
        vm.warp(block.timestamp + 31); // 31 seconds later
        vm.prank(address(mockStableGuard));
        liquidationManager.liquidate(user, address(mockToken), DEBT_AMOUNT);
    }

    function test_MEVProtection_BlockLimit() public {
        mockCollateral.setTotalCollateralValue(user, 1100e18);

        address liquidator1 = makeAddr("liquidator1");
        address liquidator2 = makeAddr("liquidator2");
        address liquidator3 = makeAddr("liquidator3");
        address liquidator4 = makeAddr("liquidator4");

        // Set up multiple liquidators as StableGuard
        vm.startPrank(owner);
        liquidationManager.setStableGuard(liquidator1);
        vm.stopPrank();

        // First 3 liquidations should succeed (different liquidators, same block)
        vm.prank(liquidator1);
        liquidationManager.liquidate(user, address(mockToken), DEBT_AMOUNT);

        // Change to liquidator2 for second liquidation
        vm.prank(owner);
        liquidationManager.setStableGuard(liquidator2);
        vm.prank(liquidator2);
        liquidationManager.liquidate(user, address(mockToken), DEBT_AMOUNT);

        // Change to liquidator3 for third liquidation
        vm.prank(owner);
        liquidationManager.setStableGuard(liquidator3);
        vm.prank(liquidator3);
        liquidationManager.liquidate(user, address(mockToken), DEBT_AMOUNT);

        // 4th liquidation in same block should fail (MAX_LIQUIDATIONS_PER_BLOCK = 3)
        vm.prank(owner);
        liquidationManager.setStableGuard(liquidator4);
        vm.prank(liquidator4);
        vm.expectRevert("Block limit exceeded");
        liquidationManager.liquidate(user, address(mockToken), DEBT_AMOUNT);
    }

    function test_MEVProtection_FlashloanDetection() public {
        // Reset to trigger flashloan detection
        vm.warp(100); // Set timestamp to pass rate limiting (MIN_LIQUIDATION_DELAY = 30)
        vm.roll(1); // Reset block number

        // Send large amount to trigger flashloan detection
        vm.deal(address(liquidationManager), 60 ether);

        mockCollateral.setTotalCollateralValue(user, 1100e18);

        vm.prank(address(mockStableGuard));
        vm.expectRevert("Flashloan protection active");
        liquidationManager.liquidate(user, address(mockToken), DEBT_AMOUNT);

        // Remove the large balance and wait for protection to expire
        vm.deal(address(liquidationManager), 0);
        vm.roll(block.number + 3); // Need > flashloanDetectionBlock + FLASHLOAN_PROTECTION_BLOCKS (2)
        vm.prank(address(mockStableGuard));
        liquidationManager.liquidate(user, address(mockToken), DEBT_AMOUNT);
    }

    function test_MEVProtection_ReputationSystem() public {
        mockCollateral.setTotalCollateralValue(user, 1100e18);

        // First liquidation establishes reputation
        vm.prank(address(mockStableGuard));
        liquidationManager.liquidate(user, address(mockToken), DEBT_AMOUNT);

        uint256 reputation = liquidationManager.getLiquidatorReputation(address(mockStableGuard));
        assertEq(reputation, 1);

        // Good behavior increases reputation
        vm.warp(block.timestamp + 61); // Wait longer than minimum delay
        vm.prank(address(mockStableGuard));
        liquidationManager.liquidate(user, address(mockToken), DEBT_AMOUNT);

        reputation = liquidationManager.getLiquidatorReputation(address(mockStableGuard));
        assertEq(reputation, 2);
    }

    function test_MEVProtection_GetBlockLiquidationCount() public {
        uint256 currentBlock = block.number;
        uint256 count = liquidationManager.getBlockLiquidationCount(currentBlock);
        assertEq(count, 0);

        mockCollateral.setTotalCollateralValue(user, 1100e18);

        vm.prank(address(mockStableGuard));
        liquidationManager.liquidate(user, address(mockToken), DEBT_AMOUNT);

        count = liquidationManager.getBlockLiquidationCount(currentBlock);
        assertEq(count, 1);
    }

    function test_MEVProtection_IsRateLimited() public {
        bool rateLimited = liquidationManager.isRateLimited(address(mockStableGuard));
        assertFalse(rateLimited);

        mockCollateral.setTotalCollateralValue(user, 1100e18);

        vm.prank(address(mockStableGuard));
        liquidationManager.liquidate(user, address(mockToken), DEBT_AMOUNT);

        rateLimited = liquidationManager.isRateLimited(address(mockStableGuard));
        assertTrue(rateLimited);

        vm.warp(block.timestamp + 31);
        rateLimited = liquidationManager.isRateLimited(address(mockStableGuard));
        assertFalse(rateLimited);
    }

    // ============ SECURITY TESTS ============

    function test_Security_ReentrancyProtection() public {
        ReentrancyAttacker attackerContract = new ReentrancyAttacker();
        attackerContract.setLiquidationManager(address(liquidationManager));
        attackerContract.setToken(address(mockToken));

        vm.prank(owner);
        liquidationManager.setStableGuard(address(attackerContract));

        mockCollateral.setTotalCollateralValue(user, 1100e18);
        mockStableGuard.setUserDebt(user, DEBT_AMOUNT);

        // Mint sufficient tokens to liquidation manager for the transfer
        mockToken.mint(address(liquidationManager), 1100e18);

        // Execute the attack
        attackerContract.attack(user, DEBT_AMOUNT);

        // Verify that the reentrancy attempt was blocked
        assertTrue(attackerContract.reentrancyBlocked(), "Reentrancy protection should have blocked the second call");

        // Verify that the attacking flag was reset (indicating the reentrancy attempt was made)
        assertFalse(attackerContract.attacking(), "Attacking flag should be false after reentrancy attempt");
    }

    function test_Security_AccessControl_OnlyOwner() public {
        // Test setStableGuard
        vm.prank(attacker);
        vm.expectRevert();
        liquidationManager.setStableGuard(attacker);

        // Test updateConfig
        vm.prank(attacker);
        vm.expectRevert();
        liquidationManager.updateConfig(16000, 13000, 1200);

        // Test liquidateDirect
        vm.prank(attacker);
        vm.expectRevert();
        liquidationManager.liquidateDirect(user, DEBT_AMOUNT);
    }

    function test_Security_AccessControl_OnlyGuard() public {
        vm.prank(attacker);
        vm.expectRevert();
        liquidationManager.liquidate(user, DEBT_AMOUNT);

        vm.prank(attacker);
        vm.expectRevert();
        liquidationManager.liquidate(user, address(mockToken), DEBT_AMOUNT);
    }

    function test_Security_EdgeCase_ZeroValues() public {
        // Test with zero collateral
        mockCollateral.setUserCollateral(user, address(mockToken), 0);

        vm.prank(address(mockStableGuard));
        vm.expectRevert(ILiquidationManager.NoCollateral.selector);
        liquidationManager.liquidate(user, address(mockToken), DEBT_AMOUNT);

        // Test with zero debt
        vm.prank(address(mockStableGuard));
        vm.expectRevert();
        liquidationManager.liquidate(user, address(mockToken), 0);
    }

    function test_Security_EdgeCase_InvalidTokenPrice() public {
        mockOracle.setTokenPrice(address(mockToken), 0);

        vm.expectRevert("Invalid token price");
        liquidationManager.calculateLiquidationAmounts(user, address(mockToken), DEBT_AMOUNT);
    }

    function test_Security_EdgeCase_MaxValues() public {
        // Use large but safe values to avoid overflow in calculations
        uint256 maxDebt = 1e30; // 1 trillion tokens with 18 decimals
        uint256 maxCollateral = 2e30; // 2 trillion tokens with 18 decimals

        mockCollateral.setTotalCollateralValue(user, maxCollateral);
        mockCollateral.setUserCollateral(user, address(mockToken), maxCollateral);
        mockStableGuard.setUserDebt(user, maxDebt);

        // Mint sufficient tokens to liquidation manager for the transfer
        mockToken.mint(address(liquidationManager), maxCollateral);

        // Should handle large values without overflow
        vm.prank(address(mockStableGuard));
        liquidationManager.liquidate(user, address(mockToken), maxDebt);
    }

    // ============ FUZZ TESTS ============

    function testFuzz_LiquidationCalculations(uint256 debtAmount, uint256 tokenPrice, uint32 bonus) public {
        // Bound inputs to reasonable ranges
        debtAmount = bound(debtAmount, 1e18, 1000000e18); // 1 to 1M
        tokenPrice = bound(tokenPrice, 1e18, 10000e18); // $1 to $10,000
        bonus = uint32(bound(bonus, 0, 2000)); // 0% to 20%

        // Update config with fuzzed bonus
        vm.prank(owner);
        liquidationManager.updateConfig(15000, 12000, bonus);

        mockOracle.setTokenPrice(address(mockToken), tokenPrice);

        (uint256 collateralAmount, uint256 liquidationBonus) =
            liquidationManager.calculateLiquidationAmounts(user, address(mockToken), debtAmount);

        // Verify calculations are reasonable
        uint256 expectedCollateral = (debtAmount * (10000 + bonus) * 1e18) / (10000 * tokenPrice);
        uint256 expectedBonus = (expectedCollateral * bonus) / 10000;

        assertEq(collateralAmount, expectedCollateral);
        assertEq(liquidationBonus, expectedBonus);

        // Verify bonus is always less than collateral amount
        assertLe(liquidationBonus, collateralAmount);
    }

    function testFuzz_CollateralRatioCalculations(uint256 collateralValue, uint256 debtValue) public {
        // Bound inputs to avoid edge cases and overflow
        collateralValue = bound(collateralValue, 1000e18, 1000000e18); // 1K to 1M tokens
        debtValue = bound(debtValue, 100e18, 1000000e18); // 100 to 1M tokens

        mockCollateral.setTotalCollateralValue(user, collateralValue);
        mockStableGuard.setUserDebt(user, debtValue);

        uint256 ratio = liquidationManager.getCollateralRatio(user);
        uint256 expectedRatio = (collateralValue * 10000) / debtValue;

        assertEq(ratio, expectedRatio);

        // Test position safety
        bool safe = liquidationManager.isPositionSafe(user, collateralValue, false);
        bool expectedSafe = expectedRatio >= 12000; // 120% liquidation threshold

        assertEq(safe, expectedSafe);
    }

    function testFuzz_ConfigValidation(uint32 minRatio, uint32 liqThreshold, uint32 bonus) public {
        // Test valid configurations
        minRatio = uint32(bound(minRatio, 11000, 50000)); // 110% to 500%
        liqThreshold = uint32(bound(liqThreshold, 10000, minRatio - 1)); // Must be less than minRatio
        bonus = uint32(bound(bonus, 0, 2000)); // 0% to 20%

        vm.prank(owner);
        liquidationManager.updateConfig(minRatio, liqThreshold, bonus);

        (, uint32 newMinRatio, uint32 newLiqThreshold, uint32 newBonus) = liquidationManager.getConfig();

        assertEq(newMinRatio, minRatio);
        assertEq(newLiqThreshold, liqThreshold);
        assertEq(newBonus, bonus);

        // Verify liquidation threshold is always less than minimum ratio
        assertLt(newLiqThreshold, newMinRatio);
    }

    // ============ EXTREME SCENARIO TESTS ============

    function test_Extreme_MassiveLiquidations() public {
        mockCollateral.setTotalCollateralValue(user, 1100e18);

        // Test multiple liquidations with time delays
        for (uint256 i = 0; i < 5; i++) {
            vm.warp(block.timestamp + 31); // Wait for rate limit
            vm.roll(block.number + 1); // New block to reset block limit

            vm.prank(address(mockStableGuard));
            bool success = liquidationManager.liquidate(user, address(mockToken), DEBT_AMOUNT);
            assertTrue(success);
        }
    }

    function test_Extreme_GasOptimization() public {
        mockCollateral.setTotalCollateralValue(user, 1100e18);

        uint256 gasBefore = gasleft();

        vm.prank(address(mockStableGuard));
        liquidationManager.liquidate(user, address(mockToken), DEBT_AMOUNT);

        uint256 gasUsed = gasBefore - gasleft();

        // Verify gas usage is reasonable (should be less than 200k gas)
        assertLt(gasUsed, 200000);
        console.log("Gas used for liquidation:", gasUsed);
    }

    function test_Extreme_HighPrecisionCalculations() public {
        // Test with very high precision values
        uint256 highPrecisionDebt = 1e30; // Very large debt
        uint256 highPrecisionPrice = 1e30; // Very high price

        mockOracle.setTokenPrice(address(mockToken), highPrecisionPrice);

        uint256 result = liquidationManager.calculateCollateralFromDebt(highPrecisionDebt, highPrecisionPrice);

        // Should handle high precision without overflow
        assertGt(result, 0);
        assertLt(result, type(uint256).max);
    }

    function test_Extreme_MultipleTokenLiquidation() public {
        // Set up multiple tokens
        MockERC20 token2 = new MockERC20("Token2", "TK2");
        MockERC20 token3 = new MockERC20("Token3", "TK3");

        mockOracle.addSupportedToken(address(token2));
        mockOracle.addSupportedToken(address(token3));
        mockOracle.setTokenPrice(address(token2), 1000e18); // $1000
        mockOracle.setTokenPrice(address(token3), 500e18); // $500
        mockOracle.setTokenDecimals(address(token2), 18);
        mockOracle.setTokenDecimals(address(token3), 18);

        // Set up collateral for multiple tokens
        mockCollateral.setUserCollateral(user, address(mockToken), 1e18); // $2000
        mockCollateral.setUserCollateral(user, address(token2), 0.5e18); // $500
        mockCollateral.setUserCollateral(user, address(token3), 2e18); // $1000
        mockCollateral.setTotalCollateralValue(user, 1100e18); // Total $1100 (liquidatable)

        // Should find optimal token (highest value = mockToken)
        address optimalToken = liquidationManager.findOptimalToken(user);
        assertEq(optimalToken, address(mockToken));

        vm.prank(address(mockStableGuard));
        bool success = liquidationManager.liquidate(user, DEBT_AMOUNT);
        assertTrue(success);
    }
}

// ============ ADDITIONAL MOCK CONTRACTS ============

contract ReentrancyAttacker {
    LiquidationManager public liquidationManager;
    bool public attacking = false;
    bool public reentrancyBlocked = false;
    address public token;

    function setLiquidationManager(address _liquidationManager) external {
        liquidationManager = LiquidationManager(_liquidationManager);
    }

    function setToken(address _token) external {
        token = _token;
    }

    function attack(address user, uint256 debtAmount) external {
        attacking = true;
        reentrancyBlocked = false;
        liquidationManager.liquidate(user, token, debtAmount);
    }

    // Legacy callback (no longer used but kept for completeness)
    function liquidate(address user, address _token, uint256 debtAmount) external returns (bool) {
        if (attacking) {
            attacking = false;
            // Attempt reentrancy
            try liquidationManager.liquidate(user, _token, debtAmount) {
                reentrancyBlocked = false;
            } catch {
                reentrancyBlocked = true;
            }
        }
        return true;
    }

    // New callback used by LiquidationManager
    function processDirectLiquidation(address user, uint256 debtAmount) external {
        if (attacking) {
            attacking = false;
            // Attempt reentrancy using stored token
            try liquidationManager.liquidate(user, token, debtAmount) {
                reentrancyBlocked = false;
            } catch {
                reentrancyBlocked = true;
            }
        }
    }

    // Required function to act as StableGuard
    function getDebt(address) external pure returns (uint256) {
        return 1000e18; // Return a debt amount for testing
    }
}

// ============ MOCK CONTRACTS ============

contract MockPriceOracle is IPriceOracle {
    mapping(address => uint256) public tokenPrices;
    mapping(address => uint8) public tokenDecimals;
    mapping(address => address) public priceFeeds;
    mapping(address => uint256) public fallbackPrices;
    mapping(address => bool) public supportedTokensMap;
    address[] public supportedTokens;

    function setTokenPrice(address token, uint256 price) external {
        tokenPrices[token] = price;
    }

    function setTokenDecimals(address token, uint8 decimals) external {
        tokenDecimals[token] = decimals;
    }

    function addSupportedToken(address token) external {
        if (!supportedTokensMap[token]) {
            supportedTokens.push(token);
            supportedTokensMap[token] = true;
        }
    }

    function getTokenPrice(address token) external view returns (uint256) {
        return tokenPrices[token];
    }

    function getTokenPriceWithEvents(address token) external returns (uint256) {
        uint256 price = tokenPrices[token];
        emit PriceUpdated(token, price, block.timestamp);
        return price;
    }

    function getTokenDecimals(address token) external view returns (uint8) {
        return tokenDecimals[token];
    }

    function getTokenValueInUsd(address token, uint256 amount) external view returns (uint256) {
        return (amount * tokenPrices[token]) / (10 ** tokenDecimals[token]);
    }

    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokens;
    }

    function isSupportedToken(address token) external view returns (bool) {
        return supportedTokensMap[token];
    }

    function configureToken(address token, address priceFeed, uint256 fallbackPrice, uint8 decimals) external {
        priceFeeds[token] = priceFeed;
        fallbackPrices[token] = fallbackPrice;
        tokenDecimals[token] = decimals;
        if (!supportedTokensMap[token]) {
            supportedTokens.push(token);
            supportedTokensMap[token] = true;
        }
        emit TokenConfigured(token, priceFeed, fallbackPrice, true);
    }

    function removeToken(address token) external {
        supportedTokensMap[token] = false;
        // Remove from array (simplified implementation)
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == token) {
                supportedTokens[i] = supportedTokens[supportedTokens.length - 1];
                supportedTokens.pop();
                break;
            }
        }
        emit TokenConfigured(token, address(0), 0, false);
    }

    function batchConfigureTokens(
        address[] calldata tokens,
        address[] calldata _priceFeeds,
        uint256[] calldata _fallbackPrices,
        uint8[] calldata decimals
    ) external {
        require(
            tokens.length == _priceFeeds.length && tokens.length == _fallbackPrices.length
                && tokens.length == decimals.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < tokens.length; i++) {
            this.configureToken(tokens[i], _priceFeeds[i], _fallbackPrices[i], decimals[i]);
        }
    }

    function getTokenConfig(address token)
        external
        view
        returns (address priceFeed, uint256 fallbackPrice, uint8 decimals)
    {
        return (priceFeeds[token], fallbackPrices[token], tokenDecimals[token]);
    }

    function getMultipleTokenPrices(address[] calldata tokens)
        external
        view
        returns (uint256[] memory prices, bool[] memory validFlags)
    {
        prices = new uint256[](tokens.length);
        validFlags = new bool[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            prices[i] = tokenPrices[tokens[i]];
            validFlags[i] = supportedTokensMap[tokens[i]];
        }
    }

    function checkFeedHealth(address token) external view returns (bool isHealthy, uint256 lastUpdate) {
        return (supportedTokensMap[token], block.timestamp);
    }

    function updateFallbackPrice(address token, uint256 newFallbackPrice) external {
        fallbackPrices[token] = newFallbackPrice;
        emit FallbackPriceUpdated(token, newFallbackPrice);
    }
}

contract MockCollateralManager is ICollateralManager {
    mapping(address => mapping(address => uint256)) public userCollateral;
    mapping(address => uint256) public totalCollateralValue;
    mapping(address => address[]) public userTokens;

    function setUserCollateral(address user, address token, uint256 amount) external {
        userCollateral[user][token] = amount;
    }

    function setTotalCollateralValue(address user, uint256 value) external {
        totalCollateralValue[user] = value;
    }

    function getUserCollateral(address user, address token) external view returns (uint256) {
        return userCollateral[user][token];
    }

    function getTotalCollateralValue(address user) external view returns (uint256) {
        return totalCollateralValue[user];
    }

    // Required interface implementations
    function addCollateralType(
        address token,
        address priceFeed,
        uint256 fallbackPrice,
        uint8 decimals,
        uint16 ltv,
        uint16 liquidationThreshold,
        uint16 liquidationPenalty
    ) external {
        // Mock implementation - does nothing
    }

    function deposit(address user, address token, uint256 amount) external payable {
        userCollateral[user][token] += amount;
        // Add token to user's token list if not already present
        address[] storage tokens = userTokens[user];
        bool found = false;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                found = true;
                break;
            }
        }
        if (!found) {
            tokens.push(token);
        }
    }

    function withdraw(address user, address token, uint256 amount) external {
        require(userCollateral[user][token] >= amount, "Insufficient collateral");
        userCollateral[user][token] -= amount;
    }

    function getUserTokens(address user) external view returns (address[] memory) {
        return userTokens[user];
    }

    function canLiquidate(address user, uint256 debtValue, uint256 liquidationThreshold) external view returns (bool) {
        uint256 collateralValue = totalCollateralValue[user];
        return collateralValue * 10000 < debtValue * liquidationThreshold;
    }

    function getCollateralRatio(address /* user */ ) external pure returns (uint256) {
        // Mock implementation - return a default ratio
        return 150; // 150%
    }

    function isCollateralSufficient(address user, uint256 debtAmount) external view returns (bool) {
        uint256 collateralValue = totalCollateralValue[user];
        return collateralValue >= debtAmount * 120 / 100; // 120% minimum ratio
    }

    function liquidateCollateral(address user, address, /* token */ uint256 debtValue, uint256 liquidationThreshold)
        external
        view
        returns (bool)
    {
        uint256 collateralValue = totalCollateralValue[user];
        return collateralValue * 10000 < debtValue * liquidationThreshold;
    }

    function emergencyWithdraw(address token, uint256 amount) external {
        // Mock implementation for emergency withdraw
        // In a real implementation, this would transfer tokens/ETH to the owner
        // For testing purposes, we just need the function to exist
    }
}

contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract MockStableGuard {
    mapping(address => uint256) public userDebt;

    function setUserDebt(address user, uint256 debt) external {
        userDebt[user] = debt;
    }

    function getDebt(address user) external view returns (uint256) {
        return userDebt[user];
    }
}
