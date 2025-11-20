// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {
    UUPSUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {
    AccessControlUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {
    Initializable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {INovaRegistry} from "../interfaces/INovaRegistry.sol";
import {INovaApp} from "../interfaces/INovaApp.sol";
import {INitroEnclaveVerifier} from "../interfaces/INitroEnclaveVerifier.sol";
import {ZkCoProcessorType, VerifierJournal} from "../types/NitroTypes.sol";
import {AttestationLib} from "../libraries/AttestationLib.sol";

/**
 * @title NovaRegistry
 * @notice Main platform contract for managing Nova TEE applications
 * @dev UUPS upgradeable contract managing app registration, activation, and lifecycle
 *
 * Key features:
 * - PCR-based app grouping (apps with same PCRs share an appId)
 * - ZK proof verification of attestation reports
 * - Heartbeat mechanism for liveness tracking
 * - Gas budget management per app instance
 * - Version tracking for app instances
 */
contract NovaRegistry is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    INovaRegistry
{
    using AttestationLib for VerifierJournal;

    /// @dev Role for admin operations (delete apps, upgrade contract)
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @dev Role for platform operations (activate apps, heartbeat updates)
    bytes32 public constant PLATFORM_ROLE = keccak256("PLATFORM_ROLE");

    /// @dev Role for Paymaster to deduct gas
    bytes32 public constant PAYMASTER_ROLE = keccak256("PAYMASTER_ROLE");

    /// @dev Nitro Enclave attestation verifier contract
    INitroEnclaveVerifier public verifier;

    /// @dev Heartbeat interval in seconds (default: 1 hour)
    uint256 public heartbeatInterval;

    /// @dev Heartbeat expiry duration in seconds (default: 24 hours)
    uint256 public heartbeatExpiry;

    /// @dev App metadata by appId (hash of PCRs)
    mapping(bytes32 => AppMetadata) private _appMetadata;

    /// @dev App instances by app contract address
    mapping(address => AppInstance) private _appInstances;

    /// @dev List of app contract addresses for each appId
    mapping(bytes32 => address[]) private _appIdToContracts;

    /// @dev Mapping to check if an app contract is already registered
    mapping(address => bool) private _isRegistered;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract
     * @param _verifier Address of the Nitro Enclave verifier contract
     * @param _admin Address to be granted admin role
     * @param _platform Address to be granted platform role
     */
    function initialize(
        address _verifier,
        address _admin,
        address _platform
    ) public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();

        if (
            _verifier == address(0) ||
            _admin == address(0) ||
            _platform == address(0)
        ) {
            revert InvalidAppContract();
        }

        verifier = INitroEnclaveVerifier(_verifier);
        heartbeatInterval = 1 hours;
        heartbeatExpiry = 24 hours;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(PLATFORM_ROLE, _platform);
    }

    /**
     * @inheritdoc INovaRegistry
     */
    function registerApp(
        address appContract,
        bytes32 pcr0,
        bytes32 pcr1,
        bytes32 pcr2
    ) external override {
        if (appContract == address(0)) {
            revert InvalidAppContract();
        }

        if (pcr0 == bytes32(0) || pcr1 == bytes32(0) || pcr2 == bytes32(0)) {
            revert InvalidPCRs();
        }

        if (_isRegistered[appContract]) {
            revert AppAlreadyRegistered();
        }

        // Verify caller is the publisher of the app contract
        address publisher = INovaApp(appContract).publisher();
        if (msg.sender != publisher) {
            revert Unauthorized();
        }

        // Verify app contract has this registry as novaPlatform
        address novaPlatform = INovaApp(appContract).novaPlatform();
        if (novaPlatform != address(this)) {
            revert Unauthorized();
        }

        // Compute app ID from PCRs
        bytes32 appId = AttestationLib.computeAppId(pcr0, pcr1, pcr2);

        // Initialize app metadata if first instance
        if (_appMetadata[appId].instanceCount == 0) {
            _appMetadata[appId] = AppMetadata({
                appId: appId,
                pcr0: pcr0,
                pcr1: pcr1,
                pcr2: pcr2,
                instanceCount: 0,
                latestVersion: 0
            });
        }

        // Increment instance count and version
        _appMetadata[appId].instanceCount++;
        uint256 version = ++_appMetadata[appId].latestVersion;

        // Create app instance
        _appInstances[appContract] = AppInstance({
            appId: appId,
            appContract: appContract,
            operator: address(0),
            walletAddress: address(0),
            version: version,
            status: InstanceStatus.Registered,
            gasUsed: 0,
            gasBudget: 0,
            lastHeartbeat: 0,
            registeredAt: block.timestamp
        });

        _appIdToContracts[appId].push(appContract);
        _isRegistered[appContract] = true;

        emit AppRegistered(appContract, appId, pcr0, pcr1, pcr2);
    }

    /**
     * @inheritdoc INovaRegistry
     */
    function activateApp(
        address appContract,
        bytes calldata output,
        ZkCoProcessorType zkCoprocessor,
        bytes calldata proofBytes
    ) external override onlyRole(PLATFORM_ROLE) {
        if (!_isRegistered[appContract]) {
            revert AppNotFound();
        }

        AppInstance storage instance = _appInstances[appContract];

        if (instance.status == InstanceStatus.Deleted) {
            revert AppNotFound();
        }

        // Verify attestation using ZK proof
        VerifierJournal memory journal = verifier.verify(
            output,
            zkCoprocessor,
            proofBytes
        );

        // Extract attestation data
        (
            address ethAddress,
            bytes32 tlsPubkeyHash,
            bytes32 pcr0,
            bytes32 pcr1,
            bytes32 pcr2
        ) = journal.extractAttestationData();

        // Validate PCRs match registered values
        AppMetadata storage metadata = _appMetadata[instance.appId];
        journal.validatePCRs(metadata.pcr0, metadata.pcr1, metadata.pcr2);

        // Update instance
        instance.operator = ethAddress;
        instance.walletAddress = ethAddress; // Initially same, will be updated when wallet is deployed
        instance.status = InstanceStatus.Active;
        instance.lastHeartbeat = block.timestamp;

        // Set operator in app contract
        INovaApp(appContract).setOperator(ethAddress);

        emit AppActivated(
            appContract,
            ethAddress,
            ethAddress,
            instance.version
        );
    }

    /**
     * @inheritdoc INovaRegistry
     */
    function heartbeat(
        address appContract
    ) external override onlyRole(PLATFORM_ROLE) {
        if (!_isRegistered[appContract]) {
            revert AppNotFound();
        }

        AppInstance storage instance = _appInstances[appContract];

        if (
            instance.status != InstanceStatus.Active &&
            instance.status != InstanceStatus.Inactive
        ) {
            revert Unauthorized();
        }

        instance.lastHeartbeat = block.timestamp;

        // Reactivate if was inactive
        if (instance.status == InstanceStatus.Inactive) {
            instance.status = InstanceStatus.Active;
        }

        emit HeartbeatUpdated(appContract, block.timestamp);
    }

    /**
     * @inheritdoc INovaRegistry
     */
    function updatePCRs(
        address appContract,
        bytes32 pcr0,
        bytes32 pcr1,
        bytes32 pcr2
    ) external override {
        if (!_isRegistered[appContract]) {
            revert AppNotFound();
        }

        if (pcr0 == bytes32(0) || pcr1 == bytes32(0) || pcr2 == bytes32(0)) {
            revert InvalidPCRs();
        }

        AppInstance storage instance = _appInstances[appContract];

        // Only publisher can request PCR update via app contract
        address publisher = INovaApp(appContract).publisher();
        if (msg.sender != appContract && msg.sender != publisher) {
            revert Unauthorized();
        }

        // Compute new app ID
        bytes32 newAppId = AttestationLib.computeAppId(pcr0, pcr1, pcr2);
        bytes32 oldAppId = instance.appId;

        // If appId changes, update metadata
        if (newAppId != oldAppId) {
            // Decrement old app metadata
            _appMetadata[oldAppId].instanceCount--;

            // Initialize or update new app metadata
            if (_appMetadata[newAppId].instanceCount == 0) {
                _appMetadata[newAppId] = AppMetadata({
                    appId: newAppId,
                    pcr0: pcr0,
                    pcr1: pcr1,
                    pcr2: pcr2,
                    instanceCount: 1,
                    latestVersion: instance.version
                });
            } else {
                _appMetadata[newAppId].instanceCount++;
            }

            // Update instance mapping
            _removeFromAppIdList(oldAppId, appContract);
            _appIdToContracts[newAppId].push(appContract);

            instance.appId = newAppId;
        } else {
            // Same appId, just update the PCR values in metadata
            _appMetadata[newAppId].pcr0 = pcr0;
            _appMetadata[newAppId].pcr1 = pcr1;
            _appMetadata[newAppId].pcr2 = pcr2;
        }

        emit PCRsUpdated(appContract, pcr0, pcr1, pcr2);
    }

    /**
     * @inheritdoc INovaRegistry
     */
    function fundApp(address appContract) external payable override {
        if (!_isRegistered[appContract]) {
            revert AppNotFound();
        }

        if (msg.value == 0) {
            revert InsufficientGasBudget();
        }

        _appInstances[appContract].gasBudget += msg.value;

        emit AppFunded(appContract, msg.sender, msg.value);
    }

    /**
     * @inheritdoc INovaRegistry
     */
    function deleteApp(
        address appContract
    ) external override onlyRole(ADMIN_ROLE) {
        if (!_isRegistered[appContract]) {
            revert AppNotFound();
        }

        AppInstance storage instance = _appInstances[appContract];

        if (instance.status == InstanceStatus.Deleted) {
            revert AppNotFound();
        }

        // Update metadata
        _appMetadata[instance.appId].instanceCount--;

        // Remove from appId list
        _removeFromAppIdList(instance.appId, appContract);

        // Mark as deleted
        instance.status = InstanceStatus.Deleted;

        emit AppDeleted(appContract);
    }

    /**
     * @inheritdoc INovaRegistry
     */
    function getAppsByPCRs(
        bytes32 pcr0,
        bytes32 pcr1,
        bytes32 pcr2
    ) external view override returns (address[] memory) {
        bytes32 appId = AttestationLib.computeAppId(pcr0, pcr1, pcr2);
        return _appIdToContracts[appId];
    }

    /**
     * @inheritdoc INovaRegistry
     */
    function getAppInstance(
        address appContract
    ) external view override returns (AppInstance memory) {
        if (!_isRegistered[appContract]) {
            revert AppNotFound();
        }
        return _appInstances[appContract];
    }

    /**
     * @inheritdoc INovaRegistry
     */
    function getAppMetadata(
        bytes32 appId
    ) external view override returns (AppMetadata memory) {
        return _appMetadata[appId];
    }

    /**
     * @inheritdoc INovaRegistry
     */
    function checkAndMarkInactive(
        address[] calldata appContracts
    ) external override {
        for (uint256 i = 0; i < appContracts.length; i++) {
            address appContract = appContracts[i];

            if (!_isRegistered[appContract]) {
                continue;
            }

            AppInstance storage instance = _appInstances[appContract];

            if (instance.status != InstanceStatus.Active) {
                continue;
            }

            // Check if heartbeat expired
            if (block.timestamp > instance.lastHeartbeat + heartbeatExpiry) {
                instance.status = InstanceStatus.Inactive;
                emit AppInactive(appContract);
            }
        }
    }

    /**
     * @inheritdoc INovaRegistry
     */
    function deductGas(
        address appContract,
        uint256 gasAmount
    ) external override onlyRole(PAYMASTER_ROLE) {
        if (!_isRegistered[appContract]) {
            revert AppNotFound();
        }

        AppInstance storage instance = _appInstances[appContract];

        if (instance.gasBudget < gasAmount) {
            revert InsufficientGasBudget();
        }

        instance.gasBudget -= gasAmount;
        instance.gasUsed += gasAmount;

        emit GasConsumed(appContract, gasAmount);
    }

    /**
     * @dev Updates wallet address for an app instance (called by AppWalletFactory)
     * @param appContract App contract address
     * @param walletAddress Deployed wallet address
     */
    function updateWalletAddress(
        address appContract,
        address walletAddress
    ) external onlyRole(PLATFORM_ROLE) {
        if (!_isRegistered[appContract]) {
            revert AppNotFound();
        }

        _appInstances[appContract].walletAddress = walletAddress;
    }

    /**
     * @dev Set heartbeat configuration
     * @param _heartbeatInterval New heartbeat interval in seconds
     * @param _heartbeatExpiry New heartbeat expiry in seconds
     */
    function setHeartbeatConfig(
        uint256 _heartbeatInterval,
        uint256 _heartbeatExpiry
    ) external onlyRole(ADMIN_ROLE) {
        heartbeatInterval = _heartbeatInterval;
        heartbeatExpiry = _heartbeatExpiry;
    }

    /**
     * @dev Set Paymaster role for gas deduction
     * @param paymaster Paymaster contract address
     */
    function setPaymaster(address paymaster) external onlyRole(ADMIN_ROLE) {
        _grantRole(PAYMASTER_ROLE, paymaster);
    }

    /**
     * @dev Internal function to remove app contract from appId list
     * @param appId App ID
     * @param appContract App contract address to remove
     */
    function _removeFromAppIdList(bytes32 appId, address appContract) private {
        address[] storage contracts = _appIdToContracts[appId];
        uint256 length = contracts.length;

        for (uint256 i = 0; i < length; i++) {
            if (contracts[i] == appContract) {
                contracts[i] = contracts[length - 1];
                contracts.pop();
                break;
            }
        }
    }

    /**
     * @dev Authorizes contract upgrades (UUPS)
     * @param newImplementation Address of new implementation
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(ADMIN_ROLE) {}
}
