# Nova TEE Platform - API Reference

**Version**: 1.0  
**Last Updated**: 2025-11-24

---

## Table of Contents

- [Overview](#overview)
- [NovaRegistry](#novaregistry)
- [TEE Verification](#tee-verification)
- [AppWalletFactory](#appwalletfactory)
- [NovaPaymaster](#novapaymaster)
- [AppWallet](#appwallet)
- [INovaApp Interface](#inovaapp-interface)
- [Data Structures](#data-structures)
- [Events Reference](#events-reference)
- [Error Codes](#error-codes)

---

## Overview

The Nova TEE Platform provides a complete framework for running TEE-backed decentralized applications with on-chain verification and gas sponsorship.

### Core Components

1. **NovaRegistry** - Central registry managing app lifecycle and attestation verification
2. **TEE Verifiers** - Multi-vendor attestation verification (Nitro, SGX, SEV)
3. **AppWalletFactory** - EIP-4337 wallet deployment
4. **NovaPaymaster** - Gas sponsorship for app operations
5. **AppWallet** - Smart contract wallet with dual control

### Key Features

- ✅ Multi-TEE vendor support (AWS Nitro, Intel SGX, AMD SEV)
- ✅ Semantic versioning with budget migration
- ✅ ZK-proof based attestation verification
- ✅ EIP-4337 Account Abstraction
- ✅ Gas-optimized batch operations
- ✅ Bounded storage growth through cleanup

---

## NovaRegistry

Main platform contract managing app lifecycle, verification, and version management.

**Address**: (Deployed contract address)  
**Proxy Pattern**: UUPS (Upgradeable)

### Constants

```solidity
uint256 public constant ATTESTATION_VALIDITY_WINDOW = 5 minutes;
uint256 public constant ATTESTATION_RETENTION_PERIOD = 7 days;
```

### Read Functions

#### getAppInstance

```solidity
function getAppInstance(address appContract) external view returns (AppInstance memory)
```

Get complete app instance details.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `appContract` | address | App contract address |

**Returns:** `AppInstance` struct

**Example:**
```solidity
AppInstance memory instance = registry.getAppInstance(0x123...);
console.log("Status:", instance.status);
console.log("Gas Budget:", instance.gasBudget);
console.log("Operator:", instance.operator);
console.log("TEE Type:", instance.teeType);
```

---

#### getAppMetadata

```solidity
function getAppMetadata(bytes32 appId) external view returns (AppMetadata memory)
```

Get metadata for apps with specific PCR values.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `appId` | bytes32 | keccak256(pcr0, pcr1, pcr2) |

**Returns:** `AppMetadata` struct containing PCRs, instance count, and version info

---

#### getAppsByPCRs

```solidity
function getAppsByPCRs(
    bytes32 pcr0,
    bytes32 pcr1,
    bytes32 pcr2
) external view returns (address[] memory)
```

Find all app instances with specific PCR values.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `pcr0` | bytes32 | PCR0 value |
| `pcr1` | bytes32 | PCR1 value |
| `pcr2` | bytes32 | PCR2 value |

**Returns:** Array of app contract addresses

**Use Case:** Discover all instances running the same code version

---

#### getAppVersion

```solidity
function getAppVersion(bytes32 appId) external view returns (AppVersion memory)
```

Get version information for a specific appId.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `appId` | bytes32 | App identifier |

**Returns:** `AppVersion` struct

**Example:**
```solidity
AppVersion memory v = registry.getAppVersion(appId);
console.log("Version:", v.semanticVersion);      // "v1.2.3"
console.log("Previous:", v.previousAppId);       // Link to v1.2.2
console.log("Deployed:", v.deployedAt);          // Timestamp
console.log("Deprecated:", v.deprecated);        // false
```

---

#### getVersionHistory

```solidity
function getVersionHistory(address appContract) external view returns (bytes32[] memory)
```

Get complete version history for an app.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `appContract` | address | App contract address |

**Returns:** Array of appIds in chronological order (oldest → newest)

**Example:**
```solidity
bytes32[] memory versions = registry.getVersionHistory(appContract);
// [v1.0.0_appId, v1.0.1_appId, v1.1.0_appId, v2.0.0_appId]

for (uint i = 0; i < versions.length; i++) {
    AppVersion memory v = registry.getAppVersion(versions[i]);
    console.log(v.semanticVersion);
}
```

---

#### heartbeatInterval

```solidity
function heartbeatInterval() external view returns (uint256)
```

Get configured heartbeat interval in seconds.

---

#### heartbeatExpiry

```solidity
function heartbeatExpiry() external view returns (uint256)
```

Get heartbeat expiry duration in seconds.

---

### Write Functions (Public)

#### registerApp

```solidity
function registerApp(
    address appContract,
    bytes32 pcr0,
    bytes32 pcr1,
    bytes32 pcr2,
    bytes32 previousAppId,
    string calldata semanticVersion
) external
```

Register a new app version with PCR values and version information.

**Access:** Must be called by app publisher

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `appContract` | address | App contract address |
| `pcr0` | bytes32 | Platform Configuration Register 0 |
| `pcr1` | bytes32 | Platform Configuration Register 1 |
| `pcr2` | bytes32 | Platform Configuration Register 2 |
| `previousAppId` | bytes32 | Previous version's appId (0x0 for first version) |
| `semanticVersion` | string | Version string (must start with 'v', max 32 chars) |

**Requirements:**
- Caller must be app's publisher (`INovaApp(appContract).publisher()`)
- App contract must reference this registry (`novaPlatform` points here)
- PCRs must not be zero
- App not already registered
- Semantic version format: starts with 'v', length ≤ 32
- If `previousAppId != 0x0`, it must exist and belong to same app

**Events Emitted:**
- `AppRegistered(appContract, appId, pcr0, pcr1, pcr2)`
- `AppVersionLinked(appContract, newAppId, previousAppId, semanticVersion)`

**Example:**
```solidity
// First version
registry.registerApp(
    0x123...,                    // app contract
    0xabc..., 0xdef..., 0x123..., // PCRs
    bytes32(0),                  // no previous version
    "v1.0.0"                     // semantic version
);

// Second version (upgrade)
bytes32 v1appId = keccak256(abi.encodePacked(oldPcr0, oldPcr1, oldPcr2));
registry.registerApp(
    0x456...,                    // new contract
    0x111..., 0x222..., 0x333..., // new PCRs
    v1appId,                     // link to v1.0.0
    "v1.0.1"                     // patch version
);
```

---

#### fundApp

```solidity
function fundApp(address appContract) external payable
```

Add funds to an app's gas budget.

**Access:** Public (anyone can fund)

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `appContract` | address | App contract to fund |

**Requirements:**
- App must be registered
- `msg.value > 0`

**Events Emitted:**
- `AppFunded(appContract, funder, amount)`

**Example:**
```solidity
// Add 1 ETH to app's budget
registry.fundApp{value: 1 ether}(appContract);

// Anyone can top up
registry.fundApp{value: 0.5 ether}(appContract);
```

---

#### migrateAppBudget

```solidity
function migrateAppBudget(
    address appContract,
    bytes32 newAppId
) external
```

Migrate entire gas budget from current version to new version.

**Access:** App publisher or app contract only

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `appContract` | address | App contract address |
| `newAppId` | bytes32 | New version's appId |

**Requirements:**
- Caller must be publisher or app contract
- New version must exist
- `appVersions[newAppId].previousAppId == currentInstance.appId`

**Process:**
1. Validates version chain link
2. Transfers entire `gasBudget` to new version
3. Marks old version as deprecated
4. Updates instance's appId reference

**Events Emitted:**
- `BudgetMigrated(appContract, fromAppId, toAppId, amount)`

**Example:**
```solidity
// After registering v2 linked to v1
bytes32 v2appId = keccak256(abi.encodePacked(newPcr0, newPcr1, newPcr2));

registry.migrateAppBudget(appContract, v2appId);
// Budget automatically transferred: v1 → v2
```

---

#### cleanupExpiredAttestations

```solidity
function cleanupExpiredAttestations(bytes32[] memory attestationHashes) external
```

Remove expired attestations from storage to prevent unbounded growth.

**Access:** Public (anyone can call)

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `attestationHashes` | bytes32[] | Array of attestation hashes to clean |

**Behavior:**
- Only removes attestations > 7 days old (`ATTESTATION_RETENTION_PERIOD`)
- Skips non-existent or recent attestations (no revert)
- Batched for gas efficiency
- Emits event only if > 0 attestations cleaned

**Events Emitted:**
- `AttestationsCleaned(count)` (if count > 0)

**Storage Impact:**
- Without cleanup: Unbounded growth (~32 bytes per attestation forever)
- With cleanup: ~450 KB steady-state (7 days × 1000 activations/day)

**Example:**
```solidity
// Collect old attestation hashes (from events or indexer)
bytes32[] memory oldHashes = new bytes32[](100);
oldHashes[0] = 0xabc...;  // 8 days old
oldHashes[1] = 0xdef...;  // 10 days old
oldHashes[2] = 0x123...;  // 2 days old (won't be deleted)

registry.cleanupExpiredAttestations(oldHashes);
// Only deletes hashes > 7 days old
```

---

### Write Functions (Platform Role)

#### activateApp

```solidity
function activateApp(
    address appContract,
    TEEType teeType,
    bytes calldata attestation,
    bytes calldata proof
) external
```

Activate an app after verifying TEE attestation and ZK proof.

**Access:** `PLATFORM_ROLE` only

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `appContract` | address | App contract address |
| `teeType` | TEEType | TEE vendor (0=Nitro, 1=SGX, 2=SEV) |
| `attestation` | bytes | Raw attestation document |
| `proof` | bytes | ZK proof data |

**Requirements:**
- App must be registered
- TEE verifier for `teeType` must be registered
- ZK proof must be valid
- Attestation timestamp within validity window (< 5 minutes old)
- Attestation not previously used (replay protection)
- Nonce not previously used
- PCRs in attestation match registered values

**Process:**
1. Look up TEE verifier for `teeType`
2. Verify attestation using ZK proof
3. Extract operator address and nonce from journal
4. Validate timestamp freshness
5. Check replay protection (attestation + nonce)
6. Mark attestation as consumed
7. Update instance status to `Active`

**Events Emitted:**
- `AppActivated(appContract, operator, walletAddress, version)`
- `AttestationConsumed(appContract, attestationHash, nonceHash, timestamp)`

**Example:**
```solidity
// Platform calls after receiving attestation from enclave
registry.activateApp(
    appContract,
    TEEType.NitroEnclave,
    attestationData,
    zkProof
);
```

---

#### heartbeat

```solidity
function heartbeat(address appContract) external
```

Update heartbeat timestamp for a single app.

**Access:** `PLATFORM_ROLE` only

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `appContract` | address | App to update |

**Requirements:**
- App must be registered
- App status must be `Active` or `Inactive`

**Behavior:**
- Updates `lastHeartbeat` to `block.timestamp`
- If status is `Inactive`, changes to `Active`

**Events Emitted:**
- `HeartbeatUpdated(appContract, timestamp)`

**Gas Cost:** ~30,000 gas

---

#### batchHeartbeat

```solidity
function batchHeartbeat(address[] memory apps) external
```

Update heartbeats for multiple apps in a single transaction.

**Access:** `PLATFORM_ROLE` only

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `apps` | address[] | Array of app contracts |

**Behavior:**
- Uses single timestamp for all apps
- Skips invalid apps (no revert)
- Skips apps not in `Active` or `Inactive` status
- Auto-reactivates `Inactive` apps

**Events Emitted:**
- `BatchHeartbeatUpdated(apps, timestamp)`

**Gas Optimization:**
| Method | 1000 Apps | Savings |
|--------|-----------|---------|
| Individual | ~30M gas | - |
| Batch | ~5M gas | **83%** |

**Example:**
```solidity
address[] memory apps = new address[](1000);
apps[0] = app1;
apps[1] = app2;
// ... fill array ...

registry.batchHeartbeat(apps);
// Updates all 1000 apps in ~5M gas
```

---

#### updateWalletAddress

```solidity
function updateWalletAddress(
    address appContract,
    address walletAddress
) external
```

Update wallet address after deployment.

**Access:** `PLATFORM_ROLE` only

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `appContract` | address | App contract |
| `walletAddress` | address | Deployed wallet address |

**Note:** During activation, `walletAddress` is initially set to `operator`. This function updates it after the platform deploys the actual EIP-4337 wallet.

---

### Write Functions (Paymaster Role)

#### deductGas

```solidity
function deductGas(
    address appContract,
    uint256 gasAmount
) external
```

Deduct gas from app's budget (called by NovaPaymaster).

**Access:** `PAYMASTER_ROLE` only

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `appContract` | address | App being charged |
| `gasAmount` | uint256 | Gas cost in wei |

**Requirements:**
- `instance.gasBudget >= gasAmount`

**Events Emitted:**
- `GasConsumed(appContract, gasAmount)`

---

### Admin Functions

#### registerTEEVerifier

```solidity
function registerTEEVerifier(
    TEEType teeType,
    address verifierAddress
) external
```

Register or update TEE verifier contract.

**Access:** `ADMIN_ROLE` only

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `teeType` | TEEType | TEE vendor type |
| `verifierAddress` | address | Verifier contract address |

**Requirements:**
- `verifierAddress != address(0)`
- Verifier implements `ITEEVerifier`
- `verifier.getTEEType() == teeType`

**Events Emitted:**
- `TEEVerifierRegistered(teeType, verifier)` (if new)
- `TEEVerifierUpdated(teeType, oldVerifier, newVerifier)` (if update)

**Example:**
```solidity
// Deploy verifier
NitroEnclaveVerifier verifier = new NitroEnclaveVerifier(
    nitroVerifierAddress,
    ZkCoProcessorType.RiscZero
);

// Register
registry.registerTEEVerifier(TEEType.NitroEnclave, address(verifier));
```

---

#### deleteApp

```solidity
function deleteApp(address appContract) external
```

Delete an app instance.

**Access:** `ADMIN_ROLE` only

**Events Emitted:**
- `AppDeleted(appContract)`

---

#### setHeartbeatConfig

```solidity
function setHeartbeatConfig(uint256 interval, uint256 expiry) external
```

Configure heartbeat parameters.

**Access:** `ADMIN_ROLE` only

---

#### setPaymaster

```solidity
function setPaymaster(address paymaster) external
```

Grant `PAYMASTER_ROLE` to an address.

**Access:** `ADMIN_ROLE` only

---

#### upgradeTo

```solidity
function upgradeTo(address newImplementation) external
```

Upgrade contract implementation (UUPS pattern).

**Access:** `ADMIN_ROLE` only

---

## TEE Verification

### ITEEVerifier Interface

Standard interface for all TEE attestation verifiers.

```solidity
interface ITEEVerifier {
    /**
     * @dev Verify attestation and return journal
     */
    function verify(
        bytes calldata attestation,
        bytes calldata proof
    ) external view returns (VerifierJournal memory);

    /**
     * @dev Return TEE type this verifier handles
     */
    function getTEEType() external pure returns (TEEType);

    /**
     * @dev Check if attestation is valid without full verification
     */
    function isAttestationValid(
        bytes calldata attestation,
        uint256 maxAge
    ) external view returns (bool);
}
```

### TEEType Enum

```solidity
enum TEEType {
    NitroEnclave,  // 0: AWS Nitro Enclaves
    IntelSGX,      // 1: Intel Software Guard Extensions
    AMDSEV         // 2: AMD Secure Encrypted Virtualization (SEV-SNP)
}
```

### Verifier Implementations

#### NitroEnclaveVerifier

Verifies AWS Nitro Enclave attestations.

**Constructor:**
```solidity
constructor(
    address _nitroVerifier,      // INitroEnclaveVerifier address
    ZkCoProcessorType _zkType    // RiscZero or Succinct
)
```

**Supported ZK Coprocessors:**
- RISC Zero
- Succinct SP1

---

#### IntelSGXVerifier

Verifies Intel SGX attestations.

**Status:** ⚠️ Placeholder (production implementation needed)

**Production Requirements:**
- Intel DCAP integration
- SGX quote verification
- TCB status validation
- Certificate chain verification

---

#### AMDSEVVerifier

Verifies AMD SEV-SNP attestations.

**Status:** ⚠️ Placeholder (production implementation needed)

**Production Requirements:**
- SEV-SNP attestation report verification
- AMD certificate chain (ARK → ASK → VCEK)
- TCB version checking
- Platform attestation key verification

---

## AppWalletFactory

Factory contract for deploying EIP-4337 smart contract wallets.

### Read Functions

#### getWallet

```solidity
function getWallet(address appContract) external view returns (address)
```

Get deployed wallet address for an app.

**Returns:** Wallet address (zero if not deployed)

---

#### getWalletAddress

```solidity
function getWalletAddress(
    address appContract,
    address operator,
    bytes32 salt
) external view returns (address)
```

Compute deterministic wallet address (before deployment).

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `appContract` | address | App contract |
| `operator` | address | Operator address |
| `salt` | bytes32 | CREATE2 salt |

**Returns:** Predicted wallet address

---

### Write Functions

#### createWallet

```solidity
function createWallet(
    address appContract,
    address operator,
    bytes32 salt
) external returns (address)
```

Deploy new app wallet using CREATE2.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `appContract` | address | App contract |
| `operator` | address | Initial operator |
| `salt` | bytes32 | CREATE2 salt |

**Returns:** Deployed wallet address

**Requirements:**
- `appContract` and `operator` not zero
- Wallet not already created for this app

**Events Emitted:**
- `WalletCreated(appContract, wallet, operator)`

**Example:**
```solidity
bytes32 salt = keccak256(abi.encodePacked(appContract, operator));
address wallet = factory.createWallet(appContract, operator, salt);
```

---

## NovaPaymaster

EIP-4337 Paymaster sponsoring gas for approved apps.

### Read Functions

#### gasPriceMarkup

```solidity
function gasPriceMarkup() external view returns (uint256)
```

Get gas price markup in basis points (100 = 1%).

---

### Write Functions

#### validatePaymasterUserOp

```solidity
function validatePaymasterUserOp(
    PackedUserOperation calldata userOp,
    bytes32 userOpHash,
    uint256 maxCost
) external returns (bytes memory context, uint256 validationData)
```

Validate if paymaster will sponsor this operation.

**Access:** EntryPoint only

**Validation Checks:**
1. Valid `paymasterAndData` format
2. App exists in registry
3. Sender is app's wallet
4. App status is `Active`
5. Sufficient gas budget

**Returns:**
- `context`: Data for `postOp`
- `validationData`: 0 if valid, 1 if invalid

---

#### postOp

```solidity
function postOp(
    PostOpMode mode,
    bytes calldata context,
    uint256 actualGasCost,
    uint256 actualUserOpFeePerGas
) external
```

Post-operation handler to deduct actual gas cost.

**Access:** EntryPoint only

---

### Admin Functions

#### setGasPriceMarkup

```solidity
function setGasPriceMarkup(uint256 markup) external
```

Set gas price markup (max 1000 = 10%).

**Access:** `ADMIN_ROLE` only

---

#### deposit

```solidity
function deposit() external payable
```

Deposit ETH to EntryPoint for sponsoring operations.

**Access:** `ADMIN_ROLE` only

---

#### withdrawFromEntryPoint

```solidity
function withdrawFromEntryPoint(
    address payable withdrawAddress,
    uint256 amount
) external
```

Withdraw from EntryPoint.

**Access:** `ADMIN_ROLE` only

---

## AppWallet

EIP-4337 smart contract wallet with dual control (operator + app contract).

### Read Functions

#### operator

```solidity
function operator() external view returns (address)
```

Get current operator address.

---

#### appContract

```solidity
function appContract() external view returns (address)
```

Get associated app contract.

---

#### entryPoint

```solidity
function entryPoint() external view returns (address)
```

Get EIP-4337 EntryPoint address.

---

#### novaPlatform

```solidity
function novaPlatform() external view returns (address)
```

Get Nova platform registry address.

---

### Write Functions

#### validateUserOp

```solidity
function validateUserOp(
    PackedUserOperation calldata userOp,
    bytes32 userOpHash,
    uint256 missingAccountFunds
) external returns (uint256 validationData)
```

Validate user operation signature.

**Access:** EntryPoint only

**Returns:** 0 if valid, 1 if invalid

---

#### execute

```solidity
function execute(
    address dest,
    uint256 value,
    bytes calldata func
) external
```

Execute a single call.

**Access:** EntryPoint only

---

#### executeBatch

```solidity
function executeBatch(
    address[] calldata dests,
    uint256[] calldata values,
    bytes[] calldata funcs
) external
```

Execute multiple calls in batch.

**Access:** EntryPoint only

---

#### updateOperator

```solidity
function updateOperator(address newOperator) external
```

Update operator address.

**Access:** Nova platform only

**Events Emitted:**
- `OperatorUpdated(oldOperator, newOperator)`

---

## INovaApp Interface

Standard interface that all Nova apps must implement.

```solidity
interface INovaApp {
    /// @dev Return publisher address
    function publisher() external view returns (address);

    /// @dev Return Nova platform address
    function novaPlatform() external view returns (address);

    /// @dev Return PCR values
    function pcr0() external view returns (bytes32);
    function pcr1() external view returns (bytes32);
    function pcr2() external view returns (bytes32);

    /// @dev Initialize with PCRs (publisher only)
    function initialize(
        bytes32 _pcr0,
        bytes32 _pcr1,
        bytes32 _pcr2
    ) external;

    /// @dev Update platform address (publisher only)
    function updatePlatform(address _novaPlatform) external;
}
```

### Example Implementation

```solidity
// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {INovaApp} from "./interfaces/INovaApp.sol";

contract MyNovaApp is INovaApp {
    address public immutable publisher;
    address public novaPlatform;
    bytes32 public pcr0;
    bytes32 public pcr1;
    bytes32 public pcr2;

    constructor(address _publisher, address _novaPlatform) {
        publisher = _publisher;
        novaPlatform = _novaPlatform;
    }

    function initialize(
        bytes32 _pcr0,
        bytes32 _pcr1,
        bytes32 _pcr2
    ) external {
        require(msg.sender == publisher, "Only publisher");
        require(pcr0 == bytes32(0), "Already initialized");
        pcr0 = _pcr0;
        pcr1 = _pcr1;
        pcr2 = _pcr2;
    }

    function updatePlatform(address _novaPlatform) external {
        require(msg.sender == publisher, "Only publisher");
        novaPlatform = _novaPlatform;
    }

    // Your app logic here
    function yourFunction() external {
        // ...
    }
}
```

---

## Data Structures

### AppInstance

```solidity
struct AppInstance {
    bytes32 appId;           // keccak256(pcr0, pcr1, pcr2)
    address appContract;     // App contract address
    address operator;        // Current operator from enclave
    address walletAddress;   // EIP-4337 wallet (initially = operator)
    uint256 version;         // Version number
    InstanceStatus status;   // Current status
    uint256 gasUsed;         // Cumulative gas consumed (wei)
    uint256 gasBudget;       // Remaining gas budget (wei)
    uint256 lastHeartbeat;   // Last heartbeat timestamp
    uint256 registeredAt;    // Registration timestamp
    TEEType teeType;         // TEE vendor used for activation
}
```

### AppMetadata

```solidity
struct AppMetadata {
    bytes32 appId;          // keccak256(pcr0, pcr1, pcr2)
    bytes32 pcr0;           // Platform Configuration Register 0
    bytes32 pcr1;           // Platform Configuration Register 1
    bytes32 pcr2;           // Platform Configuration Register 2
    uint256 instanceCount;  // Number of instances with these PCRs
    uint256 latestVersion;  // Latest version number
}
```

### AppVersion

```solidity
struct AppVersion {
    bytes32 appId;           // keccak256(pcr0, pcr1, pcr2)
    bytes32 previousAppId;   // Link to previous version (0x0 for first)
    uint256 deployedAt;      // Deployment timestamp
    string semanticVersion;  // "v1.2.3" format
    bool deprecated;         // true after budget migrated away
}
```

### VerifierJournal

```solidity
struct VerifierJournal {
    bytes32 pcr0;           // Extracted from attestation
    bytes32 pcr1;
    bytes32 pcr2;
    address ethAddress;     // Operator eth address
    bytes nonce;            // Unique nonce for replay protection
    uint64 timestamp;       // Attestation timestamp (milliseconds)
}
```

### Enums

```solidity
enum InstanceStatus {
    Registered,  // App registered, awaiting activation
    Active,      // App running and verified
    Inactive,    // Heartbeat expired
    Deleted      // Deleted by admin
}

enum TEEType {
    NitroEnclave,  // AWS Nitro Enclaves
    IntelSGX,      // Intel SGX
    AMDSEV         // AMD SEV-SNP
}

enum ZkCoProcessorType {
    RiscZero,   // RISC Zero
    Succinct    // Succinct SP1
}
```

---

## Events Reference

### NovaRegistry Events

```solidity
// Registration & Versioning
event AppRegistered(
    address indexed appContract,
    bytes32 indexed appId,
    bytes32 pcr0,
    bytes32 pcr1,
    bytes32 pcr2
);

event AppVersionLinked(
    address indexed appContract,
    bytes32 indexed newAppId,
    bytes32 indexed previousAppId,
    string semanticVersion
);

// Activation & Lifecycle
event AppActivated(
    address indexed appContract,
    address indexed operator,
    address walletAddress,
    uint256 version
);

event AppInactive(address indexed appContract);

event AppDeleted(address indexed appContract);

// Heartbeats
event HeartbeatUpdated(
    address indexed appContract,
    uint256 timestamp
);

event BatchHeartbeatUpdated(
    address[] apps,
    uint256 timestamp
);

// Budget Management
event AppFunded(
    address indexed appContract,
    address indexed funder,
    uint256 amount
);

event GasConsumed(
    address indexed appContract,
    uint256 amount
);

event BudgetMigrated(
    address indexed appContract,
    bytes32 indexed fromAppId,
    bytes32 indexed toAppId,
    uint256 amount
);

// Security & Attestation
event AttestationConsumed(
    address indexed appContract,
    bytes32 indexed attestationHash,
    bytes32 indexed nonceHash,
    uint64 timestamp
);

event AttestationsCleaned(uint256 count);

// TEE Verification
event TEEVerifierRegistered(
    TEEType indexed teeType,
    address indexed verifier
);

event TEEVerifierUpdated(
    TEEType indexed teeType,
    address indexed oldVerifier,
    address indexed newVerifier
);
```

### AppWalletFactory Events

```solidity
event WalletCreated(
    address indexed appContract,
    address indexed wallet,
    address indexed operator
);
```

### AppWallet Events

```solidity
event OperatorUpdated(
    address indexed oldOperator,
    address indexed newOperator
);
```

---

## Error Codes

### NovaRegistry Errors

```solidity
error AppAlreadyRegistered();      // App already registered
error AppNotFound();                // App does not exist
error InvalidPCRs();                // PCR values are zero
error InvalidAppContract();         // App contract address is zero
error VerificationFailed();         // Attestation verification failed
error InsufficientGasBudget();      // Not enough gas budget
error Unauthorized();               // Caller not authorized
error AttestationAlreadyUsed();     // Attestation hash already consumed
error NonceAlreadyUsed();           // Nonce already used
error AttestationExpired();         // Attestation too old
error AttestationFromFuture();      // Attestation timestamp in future
error TEEVerifierNotRegistered();   // No verifier for TEE type
error InvalidTEEVerifier();         // Invalid verifier address
error InvalidVersionChain();        // Version chain validation failed
error InvalidSemanticVersion();     // Invalid version format
```

---

**Last Updated**: 2025-11-24  
**Version**: 1.0  
**License**: Apache-2.0
