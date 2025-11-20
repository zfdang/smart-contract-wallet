// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {IAccount, PackedUserOperation} from "../interfaces/IEntryPoint.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title AppWallet
 * @notice EIP-4337 smart contract wallet with dual control mechanism
 * @dev Operator controls business operations, Nova platform manages infrastructure
 *
 * Key features:
 * - EIP-4337 compliant account abstraction
 * - Dual control: operator executes operations, Nova platform can update operator
 * - Minimal implementation for enclave-based applications
 */
contract AppWallet is IAccount {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    /// @dev EntryPoint contract address (EIP-4337 v0.7)
    address public immutable entryPoint;

    /// @dev Nova platform registry contract
    address public immutable novaPlatform;

    /// @dev Current operator address (enclave wallet)
    address public operator;

    /// @dev App contract this wallet belongs to
    address public immutable appContract;

    /**
     * @dev Emitted when operator is updated
     */
    event OperatorUpdated(address indexed oldOperator, address indexed newOperator);

    /**
     * @dev Error thrown when caller is not authorized
     */
    error Unauthorized();

    /**
     * @dev Error thrown when caller is not EntryPoint
     */
    error NotFromEntryPoint();

    /**
     * @dev Error thrown when execution fails
     */
    error ExecutionFailed();

    /**
     * @dev Modifier to check caller is EntryPoint
     */
    modifier onlyEntryPoint() {
        if (msg.sender != entryPoint) {
            revert NotFromEntryPoint();
        }
        _;
    }

    /**
     * @dev Modifier to check caller is Nova platform
     */
    modifier onlyNovaPlatform() {
        if (msg.sender != novaPlatform) {
            revert Unauthorized();
        }
        _;
    }

    /**
     * @dev Constructor
     * @param _entryPoint EntryPoint contract address
     * @param _novaPlatform Nova platform contract address
     * @param _appContract App contract address
     * @param _operator Initial operator address
     */
    constructor(address _entryPoint, address _novaPlatform, address _appContract, address _operator) {
        entryPoint = _entryPoint;
        novaPlatform = _novaPlatform;
        appContract = _appContract;
        operator = _operator;
    }

    /**
     * @inheritdoc IAccount
     * @dev Validates user operation signature
     */
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        override
        onlyEntryPoint
        returns (uint256 validationData)
    {
        // Verify signature from current operator
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        address signer = hash.recover(userOp.signature);

        if (signer != operator) {
            return 1; // Signature validation failed
        }

        // Pay required funds to EntryPoint if needed
        if (missingAccountFunds > 0) {
            (bool success,) = payable(entryPoint).call{value: missingAccountFunds}("");
            if (!success) {
                return 1;
            }
        }

        return 0; // Validation successful
    }

    /**
     * @dev Execute a call from this wallet
     * @param dest Destination address
     * @param value ETH value to send
     * @param func Calldata to execute
     */
    function execute(address dest, uint256 value, bytes calldata func) external onlyEntryPoint {
        _call(dest, value, func);
    }

    /**
     * @dev Execute a batch of calls from this wallet
     * @param dests Array of destination addresses
     * @param values Array of ETH values
     * @param funcs Array of calldata
     */
    function executeBatch(address[] calldata dests, uint256[] calldata values, bytes[] calldata funcs)
        external
        onlyEntryPoint
    {
        require(dests.length == values.length && dests.length == funcs.length, "Length mismatch");

        for (uint256 i = 0; i < dests.length; i++) {
            _call(dests[i], values[i], funcs[i]);
        }
    }

    /**
     * @dev Update operator address (Nova platform only)
     * @param newOperator New operator address
     */
    function updateOperator(address newOperator) external onlyNovaPlatform {
        require(newOperator != address(0), "Invalid operator");

        address oldOperator = operator;
        operator = newOperator;

        emit OperatorUpdated(oldOperator, newOperator);
    }

    /**
     * @dev Internal function to execute a call
     * @param dest Destination address
     * @param value ETH value
     * @param func Calldata
     */
    function _call(address dest, uint256 value, bytes memory func) internal {
        (bool success, bytes memory result) = dest.call{value: value}(func);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /**
     * @dev Receive function to accept ETH
     */
    receive() external payable {}

    /**
     * @dev Fallback function
     */
    fallback() external payable {}
}
