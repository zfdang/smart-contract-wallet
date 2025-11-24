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
import {ITEEVerifier} from "../interfaces/ITEEVerifier.sol";
import {ZkCoProcessorType, VerifierJournal, Pcr, TEEType} from "../types/NitroTypes.sol";
import {AttestationLib} from "../libraries/AttestationLib.sol";

/**
 * @title NovaRegistry
 * @notice Main platform contract for managing Nova TEE applications
 * @dev UUPS upgradeable contract managing app registration, activation, and lifecycle
 *
 * Key features:
 * - PCR-based app grouping (apps with same PCRs share an appId)
 * - ZK proof verification of attestation reports
 * - Attestation replay protection with nonce tracking
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

    /// @dev Mapping of TEE type to verifier contract
    mapping(TEEType => ITEEVerifier) public teeVerifiers;
    
    /// @dev Legacy Nitro Enclave attestation verifier contract (deprecated, use teeVerifiers)
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

    /// @dev Tracks used attestation hashes to prevent replay attacks
    mapping(bytes32 => bool) private _usedAttestations;

    /// @dev Tracks used nonces to prevent replay attacks (extra layer)
    mapping(bytes32 => bool) private _usedNonces;

    /// @dev Time window for attestation validity (5 minutes)
    uint256 public constant ATTESTATION_VALIDITY_WINDOW = 5 minutes;

    /// @dev Mapping of appId to version information
    mapping(bytes32 => AppVersion) private _appVersions;

    /// @dev Mapping of appContract to list of all appId versions (chronological)
    mapping(address => bytes32[]) private _versionHistory;

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
        bytes32 pcr2,
        bytes32 previousAppId,
        string calldata semanticVersion
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

        // Validate semantic version format
        _validateSemanticVersion(semanticVersion);

        // Compute app ID from PCRs
        bytes32 appId = AttestationLib.computeAppId(pcr0, pcr1, pcr2);

        // Validate version chain
        _validateVersionChain(appContract, appId, previousAppId);

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

        // Create version record
        _appVersions[appId] = AppVersion({
            appId: appId,
            previousAppId: previousAppId,
            deployedAt: block.timestamp,
            semanticVersion: semanticVersion,
            deprecated: false
        });

        // Add to version history
        _versionHistory[appContract].push(appId);

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
            registeredAt: block.timestamp,
            teeType: TEEType.NitroEnclave // Default, will be set during activation
        });

        _appIdToContracts[appId].push(appContract);
        _isRegistered[appContract] = true;

        emit AppRegistered(appContract, appId, pcr0, pcr1, pcr2);
        emit AppVersionLinked(appContract, appId, previousAppId, semanticVersion);
    }

    /**
     * @inheritdoc INovaRegistry
     */
    function activateApp(
        address appContract,
        TEEType teeType,
        bytes calldata attestation,
        bytes calldata proof
    ) external override onlyRole(PLATFORM_ROLE) {
        if (!_isRegistered[appContract]) {
            revert AppNotFound();
        }

        AppInstance storage instance = _appInstances[appContract];

        if (instance.status == InstanceStatus.Deleted) {
            revert AppNotFound();
        }

        // Get the appropriate TEE verifier
        ITEEVerifier teeVerifier = teeVerifiers[teeType];
        if (address(teeVerifier) == address(0)) {
            revert TEEVerifierNotRegistered();
        }

        // Verify attestation using TEE-specific verifier
        VerifierJournal memory journal = teeVerifier.verify(
            attestation,
            proof
        );

        // Validate and consume attestation to prevent replay attacks
        _validateAndConsumeAttestation(journal, appContract);

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
        instance.teeType = teeType; // Store which TEE vendor was used

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
     * @dev Validates and marks attestation as used to prevent replay attacks
     * @param journal VerifierJournal from attestation verification
     * @param appContract App contract being activated
     *
     * Security measures:
     * 1. Validates attestation timestamp freshness
     * 2. Computes unique attestation hash from all critical fields
     * 3. Checks if attestation hash already used
     * 4. Checks if nonce already used (extra layer)
     * 5. Marks both as used to prevent future replay
     */
    function _validateAndConsumeAttestation(
        VerifierJournal memory journal,
        address appContract
    ) internal {
        // 1. Validate timestamp freshness
        _validateAttestationTimestamp(journal.timestamp);

        // 2. Compute attestation hash (includes all critical fields)
        bytes32 attestationHash = _computeAttestationHash(journal);

        // 3. Check if attestation already used
        if (_usedAttestations[attestationHash]) {
            revert AttestationAlreadyUsed();
        }

        // 4. Check if nonce already used (extra layer of protection)
        bytes32 nonceHash = keccak256(journal.nonce);
        if (_usedNonces[nonceHash]) {
            revert NonceAlreadyUsed();
        }

        // 5. Mark both as used
        _usedAttestations[attestationHash] = true;
        _usedNonces[nonceHash] = true;

        emit AttestationConsumed(
            appContract,
            attestationHash,
            nonceHash,
            journal.timestamp
        );
    }

    /**
     * @dev Validates attestation timestamp is within acceptable window
     * @param attestationTimestamp Timestamp from attestation (milliseconds)
     *
     * Checks:
     * - Attestation is not from the future (allows 1 min clock drift)
     * - Attestation is not too old (within ATTESTATION_VALIDITY_WINDOW)
     */
    function _validateAttestationTimestamp(uint64 attestationTimestamp) internal view {
        // Convert milliseconds to seconds
        uint256 attestationTime = uint256(attestationTimestamp) / 1000;
        uint256 currentTime = block.timestamp;

        // Check attestation is not from future (allow small clock drift)
        if (attestationTime > currentTime + 1 minutes) {
            revert AttestationFromFuture();
        }

        // Check attestation is not too old
        if (currentTime > attestationTime + ATTESTATION_VALIDITY_WINDOW) {
            revert AttestationExpired();
        }
    }

    /**
     * @dev Computes unique hash for attestation to prevent replay
     * @param journal VerifierJournal from attestation verification
     * @return Hash of attestation including all fields that make it unique
     *
     * Hash includes:
     * - timestamp: When attestation was generated
     * - nonce: Random value for uniqueness
     * - userData: ETH address and TLS pubkey
     * - publicKey: Enclave public key
     * - moduleId: AWS Nitro module identifier
     * - pcrs: Platform Configuration Registers
     * - certs: Certificate chain hashes
     */
    function _computeAttestationHash(
        VerifierJournal memory journal
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                journal.timestamp,
                journal.nonce,
                journal.userData,
                journal.publicKey,
                journal.moduleId,
                _encodePCRs(journal.pcrs),
                _encodeCerts(journal.certs)
            )
        );
    }

    /**
     * @dev Helper function to encode PCR array for hashing
     * @param pcrs Array of Platform Configuration Registers
     * @return Hash of encoded PCR data
     */
    function _encodePCRs(Pcr[] memory pcrs) internal pure returns (bytes32) {
        bytes memory encoded;
        for (uint256 i = 0; i < pcrs.length; i++) {
            encoded = abi.encodePacked(
                encoded,
                pcrs[i].index,
                pcrs[i].value.first,
                pcrs[i].value.second
            );
        }
        return keccak256(encoded);
    }

    /**
     * @dev Helper function to encode certificate array for hashing
     * @param certs Array of certificate hashes
     * @return Hash of certificate chain
     */
    function _encodeCerts(bytes32[] memory certs) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(certs));
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
    function migrateAppBudget(
        address appContract,
        bytes32 newAppId
    ) external override {
        if (!_isRegistered[appContract]) {
            revert AppNotFound();
        }

        AppInstance storage instance = _appInstances[appContract];

        // Only publisher or app contract can migrate
        address publisher = INovaApp(appContract).publisher();
        if (msg.sender != publisher && msg.sender != appContract) {
            revert Unauthorized();
        }

        bytes32 currentAppId = instance.appId;

        // Verify version chain link
        AppVersion storage newVersion = _appVersions[newAppId];
        if (newVersion.appId == bytes32(0)) {
            revert InvalidVersionChain();
        }
        if (newVersion.previousAppId != currentAppId) {
            revert InvalidVersionChain();
        }

        // Get current budget
        uint256 budgetToTransfer = instance.gasBudget;

        // Update instance to new version
        instance.appId = newAppId;

        // Mark old version as deprecated
        _appVersions[currentAppId].deprecated = true;

        // Update app Id lists
        _removeFromAppIdList(currentAppId, appContract);
        _appIdToContracts[newAppId].push(appContract);

        emit BudgetMigrated(appContract, currentAppId, newAppId, budgetToTransfer);
    }

    /**
     * @inheritdoc INovaRegistry
     */
    function getAppVersion(bytes32 appId) external view override returns (AppVersion memory) {
        return _appVersions[appId];
    }

    /**
     * @inheritdoc INovaRegistry
     */
    function getVersionHistory(address appContract) external view override returns (bytes32[] memory) {
        return _versionHistory[appContract];
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
     * @dev Register or update a TEE verifier for a specific TEE type
     * @param teeType Type of TEE (NitroEnclave, IntelSGX, or AMDSEV)
     * @param verifierAddress Address of the TEE verifier contract
     */
    function registerTEEVerifier(
        TEEType teeType,
        address verifierAddress
    ) external onlyRole(ADMIN_ROLE) {
        if (verifierAddress == address(0)) {
            revert InvalidTEEVerifier();
        }

        // Verify the contract implements ITEEVerifier
        ITEEVerifier newVerifier = ITEEVerifier(verifierAddress);
        
        // Verify the verifier reports the correct TEE type
        require(newVerifier.getTEEType() == teeType, "TEEType mismatch");

        address oldVerifier = address(teeVerifiers[teeType]);
        teeVerifiers[teeType] = newVerifier;

        if (oldVerifier == address(0)) {
            emit TEEVerifierRegistered(teeType, verifierAddress);
        } else {
            emit TEEVerifierUpdated(teeType, oldVerifier, verifierAddress);
        }
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
     * @dev Validates semantic version format
     * @param version Semantic version string (must start with 'v')
     */
    function _validateSemanticVersion(string memory version) private pure {
        bytes memory versionBytes = bytes(version);
        
        if (versionBytes.length == 0) {
            revert InvalidSemanticVersion();
        }
        
        if (versionBytes.length > 32) {
            revert InvalidSemanticVersion();
        }
        
        if (versionBytes[0] != 'v') {
            revert InvalidSemanticVersion();
        }
        
        // Additional format validation could be added here
        // For now, we just check it starts with 'v' and has reasonable length
    }

    /**
     * @dev Validates version chain integrity
     * @param appContract App contract address
     * @param newAppId New version's appId
     * @param previousAppId Previous version's appId (0x0 for first version)
     */
    function _validateVersionChain(
        address appContract,
        bytes32 newAppId,
        bytes32 previousAppId
    ) private view {
        // If this is the first version, no validation needed
        if (previousAppId == bytes32(0)) {
            return;
        }

        // Verify previous version exists
        AppVersion storage prevVersion = _appVersions[previousAppId];
        if (prevVersion.appId == bytes32(0)) {
            revert InvalidVersionChain();
        }

        // Verify previous version belongs to same app contract
        bytes32[] storage history = _versionHistory[appContract];
        bool found = false;
        for (uint256 i = 0; i < history.length; i++) {
            if (history[i] == previousAppId) {
                found = true;
                break;
            }
        }
        
        if (!found) {
            revert InvalidVersionChain();
        }

        // Prevent linking to self
        if (newAppId == previousAppId) {
            revert InvalidVersionChain();
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
