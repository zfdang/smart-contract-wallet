// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

/**
 * @title UserOperation
 * @notice User operation struct for EIP-4337 v0.7
 */
struct PackedUserOperation {
    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    bytes32 accountGasLimits;
    uint256 preVerificationGas;
    bytes32 gasFees;
    bytes paymasterAndData;
    bytes signature;
}

/**
 * @title IEntryPoint
 * @notice Interface for EIP-4337 EntryPoint contract (v0.7)
 * @dev Simplified interface with essential functions for the Nova platform
 */
interface IEntryPoint {
    /**
     * @dev Execute a batch of UserOperations
     * @param ops Array of UserOperations to execute
     * @param beneficiary Address to receive gas refunds
     */
    function handleOps(PackedUserOperation[] calldata ops, address payable beneficiary) external;

    /**
     * @dev Execute aggregated UserOperations
     * @param opsPerAggregator Array of operations grouped by aggregator
     * @param beneficiary Address to receive gas refunds
     */
    function handleAggregatedOps(UserOpsPerAggregator[] calldata opsPerAggregator, address payable beneficiary)
        external;

    /**
     * @dev Get the deposit for an account
     * @param account Account address
     * @return Deposit amount
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Deposit funds for an account
     * @param account Account to deposit for
     */
    function depositTo(address account) external payable;

    /**
     * @dev Withdraw deposit
     * @param withdrawAddress Address to send funds to
     * @param withdrawAmount Amount to withdraw
     */
    function withdrawTo(address payable withdrawAddress, uint256 withdrawAmount) external;
}

/**
 * @dev User operations per aggregator
 */
struct UserOpsPerAggregator {
    PackedUserOperation[] userOps;
    address aggregator;
    bytes signature;
}

/**
 * @title IAccount
 * @notice Interface for EIP-4337 account contract
 */
interface IAccount {
    /**
     * @dev Validate user operation signature and nonce
     * @param userOp User operation to validate
     * @param userOpHash Hash of the user operation
     * @param missingAccountFunds Amount of funds missing for the operation
     * @return validationData Packed validation data (deadline, aggregator, signature valid)
     */
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        returns (uint256 validationData);
}

/**
 * @title IPaymaster
 * @notice Interface for EIP-4337 Paymaster contract
 */
interface IPaymaster {
    /**
     * @dev Validate paymaster will sponsor this operation
     * @param userOp User operation to validate
     * @param userOpHash Hash of the user operation
     * @param maxCost Maximum cost of the operation
     * @return context Arbitrary data to pass to postOp
     * @return validationData Packed validation data
     */
    function validatePaymasterUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 maxCost)
        external
        returns (bytes memory context, uint256 validationData);

    /**
     * @dev Post-operation handler
     * @param mode Execution mode (success, revert, postOpRevert)
     * @param context Data from validatePaymasterUserOp
     * @param actualGasCost Actual gas cost of the operation
     * @param actualUserOpFeePerGas Actual fee per gas
     */
    function postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost, uint256 actualUserOpFeePerGas)
        external;
}

/**
 * @dev Post-operation execution mode
 */
enum PostOpMode {
    opSucceeded,
    opReverted,
    postOpReverted
}
