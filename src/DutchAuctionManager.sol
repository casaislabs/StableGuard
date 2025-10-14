// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Constants} from "./Constants.sol";
import {IDutchAuctionManager} from "./interfaces/IDutchAuctionManager.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {ICollateralManager} from "./interfaces/ICollateralManager.sol";

/// @title DutchAuctionManager - Ultra Gas Optimized with Enhanced Security
/// @dev Implements reentrancy protection and robust validation patterns
contract DutchAuctionManager is IDutchAuctionManager, ReentrancyGuard {
    // ============ ULTRA-COMPACT ERRORS ============
    error AuctionExpired();

    // ============ ULTRA-PACKED CONSTANTS ============
    uint256 private constant INCENTIVE_PER_CLEANUP = 1e16; // 0.01 ETH

    // ============ MEV PROTECTION CONSTANTS ============
    uint256 private constant COMMIT_DURATION = 300; // 5 minutes
    uint256 private constant REVEAL_DURATION = 600; // 10 minutes
    uint256 private constant MIN_BID_DELAY = 12; // 12 seconds minimum between bids
    uint256 private constant MAX_PRICE_IMPACT = 500; // 5% max price impact
    uint256 private constant FLASHLOAN_PROTECTION_BLOCKS = 2; // 2 blocks protection

    // ============ IMMUTABLES ============
    address public immutable OWNER;
    IPriceOracle public immutable PRICE_ORACLE;
    ICollateralManager public immutable COLLATERAL_MANAGER;

    // ============ ULTRA-OPTIMIZED STATE ============
    address public stableGuard;
    uint256 public nextAuctionId = 1;

    // Ultra-packed config (32 bytes = 1 slot)
    struct Config {
        uint64 duration;
        uint64 minPriceFactor;
        uint64 liquidationBonus;
        uint64 reserved;
    }

    Config public config;

    // ============ MEV PROTECTION STRUCTURES ============
    struct BidCommit {
        bytes32 commitHash; // 32 bytes - keccak256(bidder, auctionId, maxPrice, nonce)
        uint64 commitTime; // 8 bytes - commit timestamp
        uint64 revealDeadline; // 8 bytes - reveal deadline
        bool revealed; // 1 byte - reveal status
    }

    struct MevProtection {
        uint64 lastBidTime; // 8 bytes - last bid timestamp
        uint64 lastBidBlock; // 8 bytes - last bid block number
        uint64 priceImpact; // 8 bytes - price impact in basis points
        uint64 flashloanBlock; // 8 bytes - flashloan detection block
    }

    // Ultra-optimized storage
    mapping(uint256 => DutchAuction) public auctions;
    mapping(address => uint256[]) private userAuctionIds;

    // ============ MEV PROTECTION STORAGE ============
    mapping(bytes32 => BidCommit) public bidCommits;
    mapping(uint256 => MevProtection) public mevProtection;
    mapping(address => uint256) public lastBidderActivity;
    mapping(address => uint256) public bidderReputation;

    // ============ MEV PROTECTION EVENTS ============
    event BidCommitted(bytes32 indexed commitHash, uint256 indexed auctionId, address indexed bidder);
    event BidRevealed(bytes32 indexed commitHash, uint256 indexed auctionId, address indexed bidder, uint256 maxPrice);
    event MEVAttemptDetected(uint256 indexed auctionId, address indexed suspect, string reason);
    event FlashloanDetected(address indexed user, uint256 blockNumber);

    // ============ ULTRA-COMPACT MODIFIERS ============
    modifier onlyOwner() {
        if (msg.sender != OWNER) revert Unauthorized();
        _;
    }

    modifier onlyStableGuard() {
        if (msg.sender != stableGuard) revert Unauthorized();
        _;
    }

    modifier validAuction(uint256 auctionId) {
        if (auctionId >= nextAuctionId || !auctions[auctionId].active) revert InvalidParameters();
        _;
    }

    modifier validAddress(address addr) {
        if (addr == address(0)) revert InvalidAddress();
        _;
    }

    // ============ MEV PROTECTION MODIFIERS ============
    modifier mevProtected(uint256 auctionId) {
        _checkMevProtection(auctionId);
        _;
        _updateMevProtection(auctionId);
    }

    modifier flashloanProtected() {
        _checkFlashloanProtection();
        _;
    }

    modifier rateLimited() {
        // Only apply rate limiting if bidder has previous activity
        if (lastBidderActivity[msg.sender] > 0) {
            require(block.timestamp >= lastBidderActivity[msg.sender] + MIN_BID_DELAY, "Rate limited");
        }
        _;
        lastBidderActivity[msg.sender] = block.timestamp;
    }

    // ============ ULTRA-OPTIMIZED CONSTRUCTOR ============
    constructor(address _priceOracle, address _collateralManager) {
        assembly {
            if or(iszero(_priceOracle), iszero(_collateralManager)) { revert(0, 0) }
        }
        OWNER = msg.sender;
        PRICE_ORACLE = IPriceOracle(_priceOracle);
        COLLATERAL_MANAGER = ICollateralManager(_collateralManager);
        config = Config({duration: 3600, minPriceFactor: 5000, liquidationBonus: 1000, reserved: 0});
    }

    // ============ ULTRA-OPTIMIZED FUNCTIONS ============
    function setStableGuard(address _stableGuard) external onlyOwner validAddress(_stableGuard) {
        stableGuard = _stableGuard;
    }

    /// @dev Ultra-optimized auction start with enhanced security
    function startDutchAuction(address user, address token, uint256 debtAmount)
        external
        onlyStableGuard
        nonReentrant
        validAddress(user)
        returns (uint256 auctionId)
    {
        // CHECKS: Input validation
        assembly {
            if iszero(debtAmount) {
                mstore(0x00, 0x4e487b71) // InvalidParameters()
                revert(0x1c, 0x04)
            }
        }

        // CHECKS: Verify collateral exists
        uint256 collateralAmount = COLLATERAL_MANAGER.getUserCollateral(user, token);
        if (collateralAmount == 0) revert NoCollateral();

        // CHECKS: Verify price oracle is working
        uint256 startPrice = PRICE_ORACLE.getTokenPrice(token);
        if (startPrice == 0) revert InvalidPrice();

        // EFFECTS: Update state before external interactions
        auctionId = nextAuctionId++;

        auctions[auctionId] = DutchAuction({
            user: user,
            token: token,
            debtAmount: uint96(debtAmount),
            collateralAmount: uint96(collateralAmount),
            startTime: uint64(block.timestamp),
            duration: uint32(config.duration),
            startPrice: uint128(startPrice),
            endPrice: uint128((startPrice * config.minPriceFactor) / 10000),
            active: true
        });

        userAuctionIds[user].push(auctionId);

        // INTERACTIONS: Emit event last
        emit AuctionEvent(auctionId, user, token, 0, uint128(collateralAmount), uint128(startPrice));
    }

    /// @dev Ultra-optimized bidding with enhanced security
    function bidOnAuction(uint256 auctionId, uint256 maxPrice)
        external
        payable
        nonReentrant
        validAuction(auctionId)
        mevProtected(auctionId)
        flashloanProtected
        rateLimited
        returns (bool)
    {
        // CHECKS: Validate auction and calculate current price
        DutchAuction storage auction = auctions[auctionId];

        // Check if auction has expired
        if (isAuctionExpired(auctionId)) revert AuctionExpired();

        // Calculate current price
        uint256 currentPrice = getCurrentPrice(auctionId);
        if (currentPrice == 0) revert AuctionExpired();
        if (currentPrice > maxPrice) revert PriceTooHigh();

        // Calculate total cost
        uint256 totalCost = (currentPrice * auction.collateralAmount) / 1e18;

        // CHECKS: Validate payment
        if (auction.token == Constants.ETH_TOKEN) {
            if (msg.value < totalCost) revert InsufficientPayment();
        } else {
            if (msg.value != 0) revert InsufficientPayment();
        }

        // EFFECTS: Update state before external interactions
        auction.active = false;

        // INTERACTIONS: Handle payments and transfers
        if (auction.token == Constants.ETH_TOKEN) {
            unchecked {
                if (msg.value > totalCost) payable(msg.sender).transfer(msg.value - totalCost);
            }
        } else {
            if (!IERC20(auction.token).transferFrom(msg.sender, address(this), totalCost)) revert TransferFailed();
        }

        _transferCollateral(auction.user, msg.sender, auction.token, auction.collateralAmount);
        emit AuctionEvent(
            auctionId, msg.sender, auction.token, 1, uint128(auction.collateralAmount), uint128(currentPrice)
        );
        return true;
    }

    /// @dev Ultra-compact auction cancellation
    function cancelExpiredAuction(uint256 auctionId) external validAuction(auctionId) {
        if (!isAuctionExpired(auctionId)) revert AuctionNotExpired();
        auctions[auctionId].active = false;
        emit AuctionEvent(auctionId, msg.sender, auctions[auctionId].token, 2, 0, 0);
        payable(msg.sender).transfer(INCENTIVE_PER_CLEANUP);
    }

    /// @dev Ultra-optimized price calculation with enhanced validation
    function getCurrentPrice(uint256 auctionId) public view returns (uint256 price) {
        if (auctionId >= nextAuctionId) return 0;

        DutchAuction storage auction = auctions[auctionId];
        if (!auction.active) return 0;

        uint256 elapsed = block.timestamp - auction.startTime;
        uint256 startPrice = auction.startPrice;
        uint256 minPrice = (startPrice * config.minPriceFactor) / 10000;

        // Return minimum price if exactly at duration
        if (elapsed == config.duration) return minPrice;

        // Return 0 if past duration (truly expired)
        if (elapsed > config.duration) return 0;

        uint256 priceReduction = ((startPrice - minPrice) * elapsed) / config.duration;

        return startPrice - priceReduction;
    }

    // Ultra-compact view functions with security validations
    function getAuction(uint256 auctionId) external view returns (DutchAuction memory) {
        if (auctionId >= nextAuctionId) revert InvalidParameters();
        return auctions[auctionId];
    }

    function getUserAuctions(address user) external view returns (uint256[] memory) {
        if (user == address(0)) revert InvalidAddress();
        return userAuctionIds[user];
    }

    function isAuctionActive(uint256 auctionId) external view returns (bool) {
        return auctions[auctionId].active && !isAuctionExpired(auctionId);
    }

    // ============ ULTRA-COMPACT UTILITIES ============
    function getConfig() external view returns (uint64, uint64, uint64) {
        return (config.duration, config.minPriceFactor, config.liquidationBonus);
    }

    function isAuctionExpired(uint256 auctionId) public view returns (bool) {
        return block.timestamp >= auctions[auctionId].startTime + config.duration;
    }

    function getAuctionCounter() external view returns (uint256) {
        return nextAuctionId - 1;
    }

    /// @dev Ultra-optimized collateral transfer
    function _transferCollateral(address, /* from */ address to, address token, uint256 amount) internal {
        if (token == Constants.ETH_TOKEN) payable(to).transfer(amount);
        else if (!IERC20(token).transfer(to, amount)) revert TransferFailed();
    }

    // ============ ULTRA-OPTIMIZED ADMIN ============
    function updateConfig(uint64 duration, uint64 minPriceFactor, uint64 liquidationBonus) external onlyOwner {
        assembly {
            if or(or(iszero(duration), iszero(minPriceFactor)), iszero(liquidationBonus)) { revert(0, 0) }
            if or(gt(minPriceFactor, 10000), gt(liquidationBonus, 10000)) { revert(0, 0) }
        }
        config = Config({
            duration: duration,
            minPriceFactor: minPriceFactor,
            liquidationBonus: liquidationBonus,
            reserved: 0
        });
        emit AuctionEvent(0, msg.sender, address(0), 4, uint128(duration), uint128(minPriceFactor));
    }

    function emergencyWithdraw(address token, uint256 amount) external onlyOwner nonReentrant {
        // CHECKS: Validate inputs
        if (amount == 0) revert InvalidParameters();

        // CHECKS: Verify available balance
        uint256 availableBalance;
        if (token == Constants.ETH_TOKEN) {
            availableBalance = address(this).balance;
        } else {
            if (token == address(0)) revert InvalidAddress();
            availableBalance = IERC20(token).balanceOf(address(this));
        }
        if (amount > availableBalance) revert InsufficientPayment();

        // INTERACTIONS: Transfer funds
        if (token == Constants.ETH_TOKEN) {
            (bool success,) = payable(OWNER).call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            if (!IERC20(token).transfer(OWNER, amount)) revert TransferFailed();
        }
    }

    /// @dev Get all active auctions
    function getActiveAuctions() external view returns (uint256[] memory activeAuctions) {
        uint256 count;

        // First pass: count active auctions
        for (uint256 i = 1; i < nextAuctionId; i++) {
            if (auctions[i].active && !isAuctionExpired(i)) {
                count++;
            }
        }

        // Second pass: populate array
        activeAuctions = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 1; i < nextAuctionId; i++) {
            if (auctions[i].active && !isAuctionExpired(i)) {
                activeAuctions[index] = i;
                index++;
            }
        }
    }

    function getUserTokenAuction(address user, address token) external view returns (uint256) {
        // Input validation - user cannot be zero address, but token can be (ETH)
        if (user == address(0)) revert InvalidAddress();

        uint256[] memory userAuctions = userAuctionIds[user];
        unchecked {
            for (uint256 i; i < userAuctions.length; ++i) {
                uint256 auctionId = userAuctions[i];
                if (auctions[auctionId].active && auctions[auctionId].token == token) return auctionId;
            }
        }
        return 0;
    }

    // ============ CLEANUP FUNCTIONS ============

    /// @dev Ultra-optimized batch cleaning with assembly
    function cleanExpiredAuctions(uint256[] calldata auctionIds) external returns (uint256 incentive) {
        uint256 cleanedCount;

        for (uint256 i = 0; i < auctionIds.length; i++) {
            uint256 auctionId = auctionIds[i];
            if (auctionId < nextAuctionId && auctions[auctionId].active && isAuctionExpired(auctionId)) {
                auctions[auctionId].active = false;
                cleanedCount++;
            }
        }

        if (cleanedCount > 0) {
            incentive = cleanedCount * INCENTIVE_PER_CLEANUP;
            payable(msg.sender).transfer(incentive);
            emit AuctionEvent(0, msg.sender, address(0), 3, uint128(cleanedCount), uint128(incentive));
        }
    }

    // ============ MEV PROTECTION FUNCTIONS ============

    /// @dev Commit-reveal scheme for MEV protection
    function commitBid(bytes32 commitHash, uint256 auctionId) external validAuction(auctionId) {
        require(commitHash != bytes32(0), "Invalid commit hash");

        bytes32 commitId;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, caller())
            mstore(add(ptr, 0x20), auctionId)
            mstore(add(ptr, 0x40), timestamp())
            commitId := keccak256(ptr, 0x60)
        }

        bidCommits[commitId] = BidCommit({
            commitHash: commitHash,
            commitTime: uint64(block.timestamp),
            revealDeadline: uint64(block.timestamp + REVEAL_DURATION),
            revealed: false
        });

        emit BidCommitted(commitHash, auctionId, msg.sender);
    }

    /// @dev Reveal bid with MEV protection
    function revealAndBid(bytes32 commitId, uint256 auctionId, uint256 maxPrice, uint256 nonce)
        external
        payable
        nonReentrant
        validAuction(auctionId)
        mevProtected(auctionId)
        flashloanProtected
        rateLimited
        returns (bool)
    {
        BidCommit storage commit = bidCommits[commitId];

        // Validate commit
        require(commit.commitTime > 0, "Invalid commit");
        require(!commit.revealed, "Already revealed");
        require(block.timestamp <= commit.revealDeadline, "Reveal deadline passed");
        require(block.timestamp >= commit.commitTime + COMMIT_DURATION, "Commit period not ended");

        // Verify commit hash
        bytes32 expectedHash;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, caller())
            mstore(add(ptr, 0x20), auctionId)
            mstore(add(ptr, 0x40), maxPrice)
            mstore(add(ptr, 0x60), nonce)
            expectedHash := keccak256(ptr, 0x80)
        }
        require(commit.commitHash == expectedHash, "Invalid reveal");

        // Mark as revealed
        commit.revealed = true;

        emit BidRevealed(commit.commitHash, auctionId, msg.sender, maxPrice);

        // Execute bid
        return _executeBid(auctionId, maxPrice);
    }

    /// @dev Internal bid execution with enhanced security
    function _executeBid(uint256 auctionId, uint256 maxPrice) internal returns (bool) {
        DutchAuction storage auction = auctions[auctionId];
        uint256 currentPrice = getCurrentPrice(auctionId);

        if (currentPrice == 0 || currentPrice > maxPrice) {
            revert PriceTooHigh();
        }

        uint256 totalCost = (currentPrice * auction.collateralAmount) / 1e18;

        // Validate payment
        if (auction.token == Constants.ETH_TOKEN) {
            if (msg.value < totalCost) revert InsufficientPayment();
        } else {
            if (msg.value != 0) revert InsufficientPayment();
        }

        // Update state
        auction.active = false;

        // Handle transfers
        if (auction.token == Constants.ETH_TOKEN) {
            unchecked {
                if (msg.value > totalCost) payable(msg.sender).transfer(msg.value - totalCost);
            }
        } else {
            if (!IERC20(auction.token).transferFrom(msg.sender, address(this), totalCost)) revert TransferFailed();
        }

        _transferCollateral(auction.user, msg.sender, auction.token, auction.collateralAmount);
        emit AuctionEvent(
            auctionId, msg.sender, auction.token, 1, uint128(auction.collateralAmount), uint128(currentPrice)
        );

        return true;
    }

    /// @dev Check MEV protection conditions
    function _checkMevProtection(uint256 auctionId) internal {
        MevProtection storage protection = mevProtection[auctionId];

        // Check minimum time between bids
        if (protection.lastBidTime > 0) {
            require(block.timestamp >= protection.lastBidTime + MIN_BID_DELAY, "Bid too frequent");
        }

        // Check block-based protection
        if (protection.lastBidBlock > 0) {
            require(block.number > protection.lastBidBlock, "Same block bid");
        }

        // Check price impact
        if (protection.priceImpact > MAX_PRICE_IMPACT) {
            emit MEVAttemptDetected(auctionId, msg.sender, "High price impact");
            revert("Price impact too high");
        }
    }

    /// @dev Update MEV protection state
    function _updateMevProtection(uint256 auctionId) internal {
        MevProtection storage protection = mevProtection[auctionId];

        uint256 currentPrice = getCurrentPrice(auctionId);
        uint256 previousPrice = protection.lastBidTime > 0
            ? _calculatePriceAtTime(auctionId, protection.lastBidTime)
            : auctions[auctionId].startPrice;

        // Calculate price impact
        uint256 priceImpact =
            previousPrice > currentPrice ? ((previousPrice - currentPrice) * 10000) / previousPrice : 0;

        protection.lastBidTime = uint64(block.timestamp);
        protection.lastBidBlock = uint64(block.number);
        protection.priceImpact = uint64(priceImpact);

        // Update bidder reputation
        if (priceImpact > MAX_PRICE_IMPACT / 2) {
            bidderReputation[msg.sender] = bidderReputation[msg.sender] > 0 ? bidderReputation[msg.sender] - 1 : 0;
        } else {
            bidderReputation[msg.sender]++;
        }
    }

    /// @dev Check flashloan protection
    function _checkFlashloanProtection() internal {
        // Simple flashloan detection: check if balance changed significantly in recent blocks
        // Exclude current transaction's ETH value to avoid false positives
        uint256 currentBalance = address(this).balance - msg.value;

        // Check if we're still in protection period from a previous detection
        if (
            mevProtection[0].flashloanBlock > 0
                && block.number <= mevProtection[0].flashloanBlock + FLASHLOAN_PROTECTION_BLOCKS
        ) {
            revert("Flashloan protection active");
        }

        // Check for new flashloan detection
        if (currentBalance > 100 ether) {
            // Only trigger if this is a new detection (different block)
            if (mevProtection[0].flashloanBlock != block.number) {
                mevProtection[0].flashloanBlock = uint64(block.number);
                emit FlashloanDetected(msg.sender, block.number);
                revert("Flashloan protection active");
            }
        }
    }

    /// @dev Calculate price at specific time
    function _calculatePriceAtTime(uint256 auctionId, uint256 timestamp) internal view returns (uint256) {
        DutchAuction storage auction = auctions[auctionId];

        if (timestamp <= auction.startTime) return auction.startPrice;

        uint256 elapsed = timestamp - auction.startTime;
        if (elapsed >= config.duration) return auction.endPrice;

        uint256 priceDiff = auction.startPrice - auction.endPrice;
        uint256 priceReduction = (priceDiff * elapsed) / config.duration;

        return auction.startPrice - priceReduction;
    }

    /// @dev Get MEV protection info
    function getMevProtection(uint256 auctionId) external view returns (MevProtection memory) {
        return mevProtection[auctionId];
    }

    /// @dev Get bidder reputation
    function getBidderReputation(address bidder) external view returns (uint256) {
        return bidderReputation[bidder];
    }

    // ============ RECEIVE FUNCTION ============

    receive() external payable {}
}
