// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Timelock - Security Layer for Critical Operations
 * @dev Implements time-delayed execution for emergency and critical operations
 */
contract Timelock is ReentrancyGuard {
    // ============ ERRORS ============
    error Unauthorized();
    error InvalidDelay();
    error InvalidTarget();
    error TransactionNotQueued();
    error TransactionAlreadyQueued();
    error TransactionNotReady();
    error TransactionExpired();
    error TransactionFailed();
    error InvalidParameters();

    // ============ EVENTS ============
    event TransactionQueued(
        bytes32 indexed txHash, address indexed target, uint256 value, string signature, bytes data, uint256 executeTime
    );

    event TransactionExecuted(
        bytes32 indexed txHash, address indexed target, uint256 value, string signature, bytes data
    );

    event TransactionCancelled(bytes32 indexed txHash);
    event DelayChanged(uint256 oldDelay, uint256 newDelay);

    // ============ CONSTANTS ============
    uint256 public constant MINIMUM_DELAY = 2 days;
    uint256 public constant MAXIMUM_DELAY = 30 days;
    uint256 public constant GRACE_PERIOD = 14 days;

    // ============ STATE VARIABLES ============
    address public immutable OWNER;
    uint256 public delay;

    mapping(bytes32 => bool) public queuedTransactions;

    // ============ MODIFIERS ============
    modifier onlyOwner() {
        if (msg.sender != OWNER) revert Unauthorized();
        _;
    }

    modifier validDelay(uint256 _delay) {
        if (_delay < MINIMUM_DELAY || _delay > MAXIMUM_DELAY) revert InvalidDelay();
        _;
    }

    // ============ CONSTRUCTOR ============
    constructor(uint256 _delay) validDelay(_delay) {
        OWNER = msg.sender;
        delay = _delay;
    }

    // ============ INTERNAL FUNCTIONS ============

    /**
     * @dev Optimized transaction hash calculation using inline assembly
     * @param target The contract to call
     * @param value ETH value to send
     * @param signature Function signature
     * @param data Encoded function parameters
     * @param executeTime When the transaction can be executed
     * @return txHash The calculated transaction hash
     */
    function _getTransactionHash(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 executeTime
    ) internal pure returns (bytes32 txHash) {
        assembly {
            // Get free memory pointer
            let ptr := mload(0x40)

            // Store target (32 bytes)
            mstore(ptr, target)

            // Store value (32 bytes)
            mstore(add(ptr, 0x20), value)

            // Store signature offset (32 bytes)
            mstore(add(ptr, 0x40), 0xa0)

            // Store data offset (32 bytes)
            let dataOffset := add(0xa0, add(0x20, mul(div(add(mload(signature), 0x1f), 0x20), 0x20)))
            mstore(add(ptr, 0x60), dataOffset)

            // Store executeTime (32 bytes)
            mstore(add(ptr, 0x80), executeTime)

            // Store signature length and data
            let sigLen := mload(signature)
            mstore(add(ptr, 0xa0), sigLen)

            // Copy signature data
            let sigDataPtr := add(signature, 0x20)
            let sigWords := div(add(sigLen, 0x1f), 0x20)
            for { let i := 0 } lt(i, sigWords) { i := add(i, 1) } {
                mstore(add(add(ptr, 0xc0), mul(i, 0x20)), mload(add(sigDataPtr, mul(i, 0x20))))
            }

            // Store data length and data
            let dataLen := mload(data)
            mstore(add(ptr, dataOffset), dataLen)

            // Copy data
            let dataDataPtr := add(data, 0x20)
            let dataWords := div(add(dataLen, 0x1f), 0x20)
            let dataStart := add(add(ptr, dataOffset), 0x20)
            for { let i := 0 } lt(i, dataWords) { i := add(i, 1) } {
                mstore(add(dataStart, mul(i, 0x20)), mload(add(dataDataPtr, mul(i, 0x20))))
            }

            // Calculate total length
            let totalLen := add(dataOffset, add(0x20, mul(dataWords, 0x20)))

            // Calculate keccak256
            txHash := keccak256(ptr, totalLen)
        }
    }

    // ============ EXTERNAL FUNCTIONS ============

    /**
     * @dev Queue a transaction for delayed execution
     * @param target The contract to call
     * @param value ETH value to send
     * @param signature Function signature
     * @param data Encoded function parameters
     * @param executeTime When the transaction can be executed
     */
    function queueTransaction(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 executeTime
    ) external onlyOwner returns (bytes32) {
        // CHECKS: Validate inputs
        if (target == address(0)) revert InvalidTarget();
        if (executeTime < block.timestamp + delay) revert InvalidParameters();

        bytes32 txHash = _getTransactionHash(target, value, signature, data, executeTime);

        if (queuedTransactions[txHash]) revert TransactionAlreadyQueued();

        // EFFECTS: Queue the transaction
        queuedTransactions[txHash] = true;

        emit TransactionQueued(txHash, target, value, signature, data, executeTime);
        return txHash;
    }

    /**
     * @dev Execute a queued transaction
     * @param target The contract to call
     * @param value ETH value to send
     * @param signature Function signature
     * @param data Encoded function parameters
     * @param executeTime When the transaction was scheduled
     */
    function executeTransaction(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 executeTime
    ) external payable onlyOwner nonReentrant returns (bytes memory) {
        bytes32 txHash = _getTransactionHash(target, value, signature, data, executeTime);

        // CHECKS: Validate transaction state
        if (!queuedTransactions[txHash]) revert TransactionNotQueued();
        if (block.timestamp < executeTime) revert TransactionNotReady();
        if (block.timestamp > executeTime + GRACE_PERIOD) revert TransactionExpired();

        // EFFECTS: Remove from queue before execution
        queuedTransactions[txHash] = false;

        // INTERACTIONS: Execute the transaction
        bytes memory callData;
        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }

        (bool success, bytes memory returnData) = target.call{value: value}(callData);
        if (!success) revert TransactionFailed();

        emit TransactionExecuted(txHash, target, value, signature, data);
        return returnData;
    }

    /**
     * @dev Cancel a queued transaction
     * @param target The contract to call
     * @param value ETH value to send
     * @param signature Function signature
     * @param data Encoded function parameters
     * @param executeTime When the transaction was scheduled
     */
    function cancelTransaction(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 executeTime
    ) external onlyOwner {
        bytes32 txHash = _getTransactionHash(target, value, signature, data, executeTime);

        if (!queuedTransactions[txHash]) revert TransactionNotQueued();

        queuedTransactions[txHash] = false;

        emit TransactionCancelled(txHash);
    }

    /**
     * @dev Change the delay for future transactions
     * @param newDelay New delay in seconds
     */
    function setDelay(uint256 newDelay) external onlyOwner validDelay(newDelay) {
        uint256 oldDelay = delay;
        delay = newDelay;

        emit DelayChanged(oldDelay, newDelay);
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @dev Check if a transaction is queued
     */
    function isTransactionQueued(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 executeTime
    ) external view returns (bool) {
        bytes32 txHash = _getTransactionHash(target, value, signature, data, executeTime);
        return queuedTransactions[txHash];
    }

    /**
     * @dev Get transaction hash
     */
    function getTransactionHash(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 executeTime
    ) external pure returns (bytes32) {
        return _getTransactionHash(target, value, signature, data, executeTime);
    }

    // ============ RECEIVE FUNCTION ============
    receive() external payable {}
}
