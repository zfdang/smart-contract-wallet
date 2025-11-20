# Nova TEE Platform - System Design Overview

## Executive Summary

The Nova TEE Platform is an innovative infrastructure that bridges **Trusted Execution Environments (TEE)** with **blockchain technology** to enable secure, verifiable, and user-friendly Web 3.0 applications. By combining AWS Nitro Enclaves with zero-knowledge proofs and EIP-4337 account abstraction, the platform provides:

- **Verifiable Computation**: All application instances are cryptographically verified
- **Gas Abstraction**: Users never pay gas fees directly
- **Automatic Grouping**: Apps running the same code are automatically discovered
- **Dual Control**: Clear separation between business logic and infrastructure management

## Problem Statement

### Challenges in TEE-Blockchain Integration

1. **Attestation Verification**: How to verify enclave attestations on-chain efficiently?
2. **Identity Management**: How to associate ephemeral enclave wallets with applications?
3. **Gas Costs**: How to provide seamless UX without users paying gas?
4. **Liveness Monitoring**: How to track if enclave instances are still running?
5. **Upgradability**: How to evolve the platform without breaking existing apps?

### Nova's Solutions

| Challenge | Solution |
|-----------|----------|
| Attestation Verification | Zero-knowledge proofs of Nitro attestations |
| Identity Management | PCR-based app grouping + operator registration |
| Gas Costs | EIP-4337 Paymaster with per-app budgets |
| Liveness Monitoring | Configurable heartbeat mechanism |
| Upgradability | UUPS proxy pattern for platform contracts |

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│                    AWS Nitro Enclave                          │
│  ┌────────────────────────────────────────────────────┐      │
│  │  User Application                                  │      │
│  │  - Generates temporary wallet keypair             │      │
│  │  - Produces attestation report                    │      │
│  │  - Signs UserOperations                           │      │
│  └────────────────────────────────────────────────────┘      │
└──────────────────────────────────────────────────────────────┘
                            ↓
                    [Attestation Report]
                            ↓
┌──────────────────────────────────────────────────────────────┐
│               Nova Platform (Off-Chain)                       │
│  - Obtains attestation from enclave                          │
│  - Generates ZK proof via coprocessor                        │
│  - Calls on-chain contracts                                  │
│  - Monitors heartbeat                                        │
└──────────────────────────────────────────────────────────────┘
                            ↓
                   [ZK Proof + Attestation]
                            ↓
┌──────────────────────────────────────────────────────────────┐
│              On-Chain Contracts (Base Sepolia)                │
│                                                               │
│  ┌─────────────────┐                                         │
│  │  NovaRegistry   │  ← Verifies ZK proofs                  │
│  │   (UUPS Proxy)  │  ← Manages app lifecycle               │
│  └────────┬────────┘  ← Tracks gas budgets                  │
│           │                                                   │
│           ├──────────► AppWalletFactory                      │
│           │            (Deploys EIP-4337 wallets)            │
│           │                                                   │
│           └──────────► NovaPaymaster                         │
│                        (Sponsors gas for apps)               │
│                                                               │
│  ┌─────────────────┐         ┌──────────────────┐          │
│  │   App Contract  │◄───────┤   AppWallet      │          │
│  │  (INovaApp)     │         │   (EIP-4337)     │          │
│  └─────────────────┘         └──────────────────┘          │
└──────────────────────────────────────────────────────────────┘
```

## Key Design Decisions

### 1. PCR-Based App Grouping

**Decision**: Use `keccak256(pcr0, pcr1, pcr2)` as app identifier

**Rationale**:
- Enables automatic discovery of instances running the same code
- Allows multiple developers to deploy the same app independently
- Provides version tracking without central coordination

**Trade-offs**:
- Apps with different PCRs (even minor code changes) get different IDs
- Requires PCR update mechanism for app upgrades

### 2. UUPS Over Transparent Proxy

**Decision**: Use UUPS (Universal Upgradeable Proxy Standard)

**Rationale**:
- Lower gas costs (upgrade logic in implementation)
- Smaller proxy contract
- Cleaner separation of concerns

**Trade-offs**:
- Implementation must include upgrade logic
- Risk of bricking if upgrade logic has bugs (mitigated by testing)

### 3. Separate Wallet Factory

**Decision**: Deploy wallet factory as separate contract

**Rationale**:
- Single responsibility principle
- Reusable across different apps
- CREATE2 for deterministic addresses

**Trade-offs**:
- Additional deployment step
- Extra transaction for wallet deployment

### 4. Dual Control Model

**Decision**: Operator controls execution, Nova platform controls operator

**Rationale**:
- Clear separation of concerns
- Operator can't lock out platform
- Platform can replace compromised operators

**Trade-offs**:
- Requires platform to act honestly
- Operator replacement needs new wallet (temporary wallets acceptable)

### 5. Heartbeat Mechanism

**Decision**: Configurable heartbeat with lazy inactive marking

**Rationale**:
- Flexible for different app requirements
- Gas-efficient (on-demand checks)
- Allows reactivation

**Trade-offs**:
- Requires off-chain monitoring
- Apps can appear active longer than they are (until check)

## Data Flow Diagrams

### App Registration Flow

```
Developer        AppContract      NovaRegistry
    |                 |                |
    |-- deploy ------>|                |
    |                 |                |
    |-- initialize -->|                |
    |    (PCRs)       |                |
    |                 |                |
    |-- registerApp ----------------->|
    |    (app, PCRs)                  |
    |                 |                |
    |                 |<- verify ------|
    |                 |   publisher    |
    |                 |                |
    |                 |<- verify ------|
    |                 |   novaPlatform |
    |                 |                |
    |<--------------- emit ------------|
    |  AppRegistered                   |
    |                 |                |
    [Status: Registered]
```

### App Activation Flow

```
Platform    Enclave    Verifier    NovaRegistry    AppContract
    |          |           |              |              |
    |-- deploy app ------->|              |              |
    |          |           |              |              |
    |          |<- generate wallet -------|              |
    |          |   (private key)          |              |
    |          |           |              |              |
    |<- attestation -------|              |              |
    |  + ETH address       |              |              |
    |          |           |              |              |
    |-- generate proof --->|              |              |
    |          |           |              |              |
    |<- ZK proof ----------|              |              |
    |          |           |              |              |
    |-- activateApp ------------------->|              |
    |    (proof)          |              |              |
    |          |           |              |              |
    |          |           |<- verify ----|              |
    |          |           |   proof      |              |
    |          |           |              |              |
    |          |           |-- journal -->|              |
    |          |           |              |              |
    |          |           |              |<- validate --|
    |          |           |              |   PCRs       |
    |          |           |              |              |
    |          |           |              |-- setOperator ->
    |          |           |              |              |
    |<------------ emit AppActivated ----|              |
    |          |           |              |              |
    [Status: Active]
```

### UserOperation Execution Flow

```
Operator    AppWallet    EntryPoint    Paymaster    NovaRegistry
   |            |             |             |              |
   |-- sign UserOp ---------->|             |              |
   |            |             |             |              |
   |            |<- validate -|             |              |
   |            |   signature |             |              |
   |            |             |             |              |
   |            |             |-- validate ->              |
   |            |             |   paymaster |              |
   |            |             |             |              |
   |            |             |             |<- get app ---|
   |            |             |             |   instance   |
   |            |             |             |              |
   |            |             |             |-- check ---->|
   |            |             |             |   budget     |
   |            |             |             |              |
   |            |             |<- accept ---|              |
   |            |             |             |              |
   |            |<- execute --|             |              |
   |            |             |             |              |
   |<- business logic --------|             |              |
   |   execution              |             |              |
   |            |             |             |              |
   |            |             |-- postOp -->|              |
   |            |             |             |              |
   |            |             |             |-- deductGas ->
   |            |             |             |              |
   [Gas deducted from budget]
```

## Security Architecture

### Trust Boundaries

```
┌─────────────────────────────────────────┐
│   Trusted Components                    │
│   - AWS Nitro Enclave hardware         │
│   - ZK Verifier contract                │
│   - EIP-4337 EntryPoint                 │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│   Semi-Trusted Components               │
│   - Nova Platform (PLATFORM_ROLE)       │
│     Can: Activate apps, heartbeat       │
│     Cannot: Modify app data, steal funds│
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│   Untrusted Components                  │
│   - App developers                      │
│   - App operators                       │
│   - General users                       │
└─────────────────────────────────────────┘
```

### Attack Surface Analysis

| Component | Attack Vector | Mitigation |
|-----------|--------------|------------|
| NovaRegistry | Fake attestation | ZK proof verification |
| NovaRegistry | PCR manipulation | Attestation validation |
| Paymaster | Unauthorized sponsorship | Budget checks, wallet verification |
| AppWallet | Signature forgery | ECDSA verification |
| App Contract | Unauthorized operator | Platform-only setOperator |

### Cryptographic Guarantees

1. **Attestation Authenticity**: ZK proof ensures attestation is from real Nitro Enclave
2. **PCR Integrity**: PCRs in attestation must match registered values
3. **Operator Identity**: ETH address extracted from verified attestation
4. **Operation Authorization**: ECDSA signature from registered operator

## Performance Characteristics

### Gas Costs

| Operation | Gas Cost | Frequency |
|-----------|----------|-----------|
| registerApp | ~120k | Once per app |
| activateApp | ~300k | Once per deployment |
| heartbeat | ~30k | Every hour |
| fundApp | ~50k | As needed |
| UserOperation | ~100-200k | Per transaction |

### Scalability Limits

- **Theoretical Max Apps**: Unlimited (storage-bound)
- **Practical Max Apps**: ~1M (gas costs for operations)
- **Apps per PCR**: Unlimited (array-based)
- **Heartbeat Throughput**: ~1000 apps per block (batched)

### Optimization Opportunities

1. **Batch Operations**: Bundle multiple heartbeats
2. **Event-Based Monitoring**: Use events instead of polling
3. **Compressed Storage**: Pack AppInstance fields
4. **L2 Deployment**: Use L2 for lower costs

## Deployment Topology

### Recommended Production Setup

```
┌─────────────────────────────────────────────────┐
│  Governance Layer                                │
│  - Gnosis Safe (Multi-sig)                      │
│  - Timelock Controller                          │
└─────────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────────┐
│  On-Chain Contracts (Base Mainnet)              │
│  - NovaRegistry (UUPS Proxy)                    │
│  - AppWalletFactory                             │
│  - NovaPaymaster                                │
└─────────────────────────────────────────────────┘
                    ↑
┌─────────────────────────────────────────────────┐
│  Platform Services                               │
│  - Attestation Verification Service             │
│  - Heartbeat Monitor                            │
│  - ZK Proof Generator                           │
│  - Event Indexer                                │
└─────────────────────────────────────────────────┘
                    ↑
┌─────────────────────────────────────────────────┐
│  AWS Infrastructure                              │
│  - EC2 Instances with Nitro Enclaves           │
│  - KMS for key management                       │
│  - CloudWatch for monitoring                    │
└─────────────────────────────────────────────────┘
```

## Future Enhancements

### Phase 2: Advanced Features

1. **Multi-Operator Support**: Allow multiple operators per app
2. **Automated Budget Refill**: Auto-refill from app balance
3. **Slashing Mechanism**: Penalize misbehaving apps
4. **Operator Rotation**: Scheduled operator updates

### Phase 3: Decentralization

1. **Decentralized Governance**: Token-based platform governance
2. **Permissionless Activation**: Remove PLATFORM_ROLE requirement
3. **Decentralized ZK Proving**: Distributed proof generation
4. **DAO Treasury**: Community-managed gas sponsorship

### Phase 4: Scaling

1. **Cross-Chain Support**: Deploy on multiple chains
2. **L2 Optimization**: Optimized for L2s (Optimism, Arbitrum)
3. **Batch Activation**: Activate multiple apps in one tx
4. **Optimistic Verification**: Reduce verification costs

## Conclusion

The Nova TEE Platform represents a novel approach to combining trusted execution environments with blockchain technology. By leveraging:

- **Zero-knowledge proofs** for verifiable computation
- **EIP-4337** for seamless user experience
- **UUPS proxies** for upgradeability
- **PCR-based grouping** for app discovery

The platform provides a robust foundation for the next generation of Web 3.0 applications that require both privacy and verifiability.

The architecture balances **security**, **usability**, and **decentralization** to create a production-ready system that can scale to thousands of applications while maintaining strong cryptographic guarantees.

---

**Document Version**: 1.0  
**Last Updated**: 2025-11-20  
**Status**: Production Ready
