# Nova TEE Platform - System Architecture

## Table of Contents

- [Overview](#overview)
- [System Components](#system-components)
- [Data Flow](#data-flow)
- [State Management](#state-management)
- [Security Model](#security-model)
- [Integration Points](#integration-points)

## Overview

The Nova TEE platform is a decentralized infrastructure for running Web 3.0 applications inside AWS Nitro Enclaves with on-chain verification and account abstraction. The system bridges trusted execution environments (TEE) with blockchain technology, providing verifiable computation with seamless user experience.

### Design Principles

1. **Trust Verification**: All enclave deployments are verified using zero-knowledge proofs of attestation reports
2. **Automatic Grouping**: Apps with identical code (PCRs) are automatically associated
3. **Gas Abstraction**: Users don't pay gas - apps have budgets managed by the platform
4. **Dual Control**: Clear separation between business logic (operator) and infrastructure (platform)
5. **Upgradeability**: Platform can evolve while maintaining compatibility

## System Components

### 1. NovaRegistry (Core Platform Contract)

The central registry managing all app instances.

#### Responsibilities

- **App Registration**: Developers register their apps with expected PCR values
- **Attestation Verification**: Validates ZK proofs of enclave attestations
- **Lifecycle Management**: Tracks app states (Registered → Active → Inactive → Deleted)
- **Heartbeat Monitoring**: Ensures app liveness through periodic updates
- **Budget Management**: Tracks gas budgets and consumption per app
- **PCR Management**: Groups apps by PCRs and handles updates

#### State Storage

```solidity
// App metadata by appId (PCR hash)
mapping(bytes32 => AppMetadata) private _appMetadata;

// App instances by contract address
mapping(address => AppInstance) private _appInstances;

// Instance lists by appId
mapping(bytes32 => address[]) private _appIdToContracts;
```

#### Access Control Roles

| Role | Capabilities | Typical Holder |
|------|-------------|----------------|
| `ADMIN_ROLE` | Delete apps, upgrade contract, configure system | Platform admin multisig |
| `PLATFORM_ROLE` | Activate apps, update heartbeats | Nova platform backend |
| `PAYMASTER_ROLE` | Deduct gas from budgets | NovaPaymaster contract |

### 2. AppWalletFactory

Factory contract for deploying deterministic EIP-4337 wallets using CREATE2.

### 3. NovaPaymaster

EIP-4337 Paymaster that sponsors gas for app operations by validating against NovaRegistry budgets.

### 4. AppWallet

EIP-4337 smart contract wallet with dual control - operator executes operations, Nova platform manages infrastructure.

### 5. App Contracts (INovaApp)

Developer-implemented contracts that integrate with the platform through a standard interface.

## Data Flow

### App Registration and Activation Flow

1. Developer deploys app contract with publisher and novaPlatform addresses
2. Developer initializes app with PCR values
3. Developer calls `registerApp()` on NovaRegistry
4. NovaRegistry validates and creates AppInstance in Registered state
5. Developer deploys app to AWS Nitro Enclave
6. Enclave generates temporary wallet keypair
7. Nova platform obtains attestation and generates ZK proof
8. Platform calls `activateApp()` with proof
9. NovaRegistry verifies proof, validates PCRs, extracts ETH address
10. NovaRegistry sets operator in app contract
11. Platform deploys AppWallet via factory
12. App instance moves to Active state

### UserOperation Execution Flow

1. Operator (enclave) signs UserOperation
2. UserOperation submitted to EntryPoint
3. EntryPoint validates via AppWallet (signature check)
4. EntryPoint validates via Paymaster (budget check)
5. Paymaster checks app status and gas budget in NovaRegistry
6. EntryPoint executes operation through AppWallet
7. Paymaster's postOp deducts actual gas cost from app budget

## State Management

### App Instance States

- **Registered**: App registered with PCRs, awaiting enclave deployment
- **Active**: Enclave running, operator set, can execute UserOperations
- **Inactive**: Heartbeat expired (>24 hours), cannot execute operations
- **Deleted**: Removed by admin, permanently inactive

### State Transitions

- Registered → Active: `activateApp()` with valid ZK proof
- Active → Active: `heartbeat()` updates lastHeartbeat
- Active → Inactive: No heartbeat for 24+ hours
- Inactive → Active: `heartbeat()` reactivates
- Any → Deleted: `deleteApp()` (admin only)

## Security Model

### Threat Mitigations

| Threat | Mitigation |
|--------|-----------|
| Fake attestations | ZK proof verification ensures authenticity |
| PCR mismatch | Attestation PCRs must match registered values |
| Operator impersonation | ECDSA signatures verified in AppWallet |
| Unauthorized activation | Only PLATFORM_ROLE can activate apps |
| Gas budget drain | Paymaster checks budget before sponsoring |
| Stale instances | Heartbeat expiry marks as Inactive |

### Trust Assumptions

1. AWS Nitro Enclave provides correct attestations
2. ZK Verifier contract correctly validates proofs  
3. Platform operator acts honestly
4. EIP-4337 EntryPoint is standard implementation

## Integration Points

### External Dependencies

1. **Nitro Enclave Verifier**: Pre-deployed contract for ZK proof verification
2. **EIP-4337 EntryPoint v0.7**: Official EntryPoint on Base Sepolia
3. **OpenZeppelin Contracts**: UUPS, AccessControl, ECDSA utilities

### Off-Chain Components

1. **Nova Platform Backend**: Monitors enclaves, generates proofs, calls activateApp/heartbeat
2. **Developer Tools**: App packaging, PCR calculation, deployment scripts

## Performance & Scalability

### Gas Cost Estimates

- registerApp(): ~120,000 gas
- activateApp(): ~300,000 gas  
- heartbeat(): ~30,000 gas
- fundApp(): ~50,000 gas

### Optimization Techniques

- Batch heartbeat updates
- Lazy inactive marking
- Packed storage in AppInstance
- Indexed events for efficient querying

## Upgrade Strategy

NovaRegistry uses UUPS proxy pattern with strict storage layout rules:
- Only ADMIN_ROLE can authorize upgrades
- New storage variables must be appended
- Never reorder or change types of existing variables

## Future Enhancements

- Multi-operator support
- Budget auto-refill
- Slashing mechanism for rule violations
- Decentralized governance
- Cross-chain deployment
- Wallet recovery mechanisms
