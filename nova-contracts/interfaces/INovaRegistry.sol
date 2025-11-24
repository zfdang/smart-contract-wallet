// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {ZkCoProcessorType, TEEType} from "../types/NitroTypes.sol";

/**
 * @title INovaRegistry
 * @notice Interface for the Nova TEE platform registry contract
 * @dev Main platform contract managing app registration, activation, and lifecycle
 */
interface INovaRegistry {
    /**
     * @dev Instance status enumeration
     */
    enum InstanceStatus {
        Registered, // App registered with PCRs, awaiting activation
        Active, // App instance running and verified
        Inactive, // App instance inactive (heartbeat expired)
        Deleted // App deleted by admin
    }

    /**
     * @dev App metadata structure (grouped by PCRs)
     */
    struct AppMetadata {
        bytes32 appId; // keccak256(pcr0, pcr1, pcr2)
        bytes32 pcr0;
        bytes32 pcr1;
        bytes32 pcr2;
        uint256 instanceCount; // Number of instances with these PCRs
        uint256 latestVersion; // Latest version number
    }

    /**
     * @dev App instance structure
     */
    struct AppInstance {
        bytes32 appId; // Reference to AppMetadata
        address appContract; // App contract address
        address operator; // Current operator address
        address walletAddress; // EIP-4337 wallet address
        uint256 version; // Version number
        InstanceStatus status; // Current status
        uint256 gasUsed; // Gas consumed (wei)
        uint256 gasBudget; // Gas budget (wei)
        uint256 lastHeartbeat; // Last heartbeat timestamp
        uint256 registeredAt; // Registration timestamp
        TEEType teeType; // TEE vendor type used for activation
    }

    // Events
    event AppRegistered(
        address indexed appContract, bytes32 indexed appId, bytes32 pcr0, bytes32 pcr1, bytes32 pcr2
    );
    event AppActivated(
        address indexed appContract, address indexed operator, address walletAddress, uint256 version
    );
    event AppInactive(address indexed appContract);
    event AppDeleted(address indexed appContract);
    event HeartbeatUpdated(address indexed appContract, uint256 timestamp);
    event PCRsUpdated(address indexed appContract, bytes32 pcr0, bytes32 pcr1, bytes32 pcr2);
    event AppFunded(address indexed appContract, address indexed funder, uint256 amount);
    event GasConsumed(address indexed appContract, uint256 amount);
    event AttestationConsumed(
        address indexed appContract, bytes32 indexed attestationHash, bytes32 indexed nonceHash, uint64 timestamp
    );
    event TEEVerifierRegistered(TEEType indexed teeType, address indexed verifier);
    event TEEVerifierUpdated(TEEType indexed teeType, address indexed oldVerifier, address indexed newVerifier);

    // Errors
    error AppAlreadyRegistered();
    error AppNotFound();
    error InvalidPCRs();
    error InvalidAppContract();
    error VerificationFailed();
    error InsufficientGasBudget();
    error Unauthorized();
    error AttestationAlreadyUsed();
    error NonceAlreadyUsed();
    error AttestationExpired();
    error AttestationFromFuture();
    error TEEVerifierNotRegistered();
    error InvalidTEEVerifier();

    /**
     * @dev Register a new app with PCRs
     * @param appContract Address of the app contract
     * @param pcr0 PCR0 value
     * @param pcr1 PCR1 value
     * @param pcr2 PCR2 value
     */
    function registerApp(address appContract, bytes32 pcr0, bytes32 pcr1, bytes32 pcr2) external;

    /**
     * @dev Activate an app instance after attestation verification
     * @param appContract App contract address
     * @param teeType TEE vendor type (NitroEnclave, IntelSGX, or AMDSEV)
     * @param attestation Raw attestation data (format varies by TEE type)
     * @param proof Zero-knowledge or cryptographic proof data
     */
    function activateApp(
        address appContract,
        TEEType teeType,
        bytes calldata attestation,
        bytes calldata proof
    ) external;

    /**
     * @dev Update app heartbeat
     * @param appContract App contract address
     */
    function heartbeat(address appContract) external;

    /**
     * @dev Update PCRs for an app
     * @param appContract App contract address
     * @param pcr0 New PCR0 value
     * @param pcr1 New PCR1 value
     * @param pcr2 New PCR2 value
     */
    function updatePCRs(address appContract, bytes32 pcr0, bytes32 pcr1, bytes32 pcr2) external;

    /**
     * @dev Fund an app's gas budget
     * @param appContract App contract address
     */
    function fundApp(address appContract) external payable;

    /**
     * @dev Delete an app (admin only)
     * @param appContract App contract address
     */
    function deleteApp(address appContract) external;

    /**
     * @dev Get all app instances with specific PCRs
     * @param pcr0 PCR0 value
     * @param pcr1 PCR1 value
     * @param pcr2 PCR2 value
     * @return Array of app contract addresses
     */
    function getAppsByPCRs(bytes32 pcr0, bytes32 pcr1, bytes32 pcr2) external view returns (address[] memory);

    /**
     * @dev Get app instance details
     * @param appContract App contract address
     * @return AppInstance struct
     */
    function getAppInstance(address appContract) external view returns (AppInstance memory);

    /**
     * @dev Get app metadata
     * @param appId App ID (hash of PCRs)
     * @return AppMetadata struct
     */
    function getAppMetadata(bytes32 appId) external view returns (AppMetadata memory);

    /**
     * @dev Check and mark inactive apps
     * @param appContracts Array of app contract addresses to check
     */
    function checkAndMarkInactive(address[] calldata appContracts) external;

    /**
     * @dev Deduct gas from app budget (called by Paymaster)
     * @param appContract App contract address
     * @param gasAmount Gas amount in wei
     */
    function deductGas(address appContract, uint256 gasAmount) external;
}
