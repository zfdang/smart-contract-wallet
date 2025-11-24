# Nova TEE Platform - System Design Diagrams

This document contains Mermaid diagram representations of the workflows and architecture described in [DESIGN.md](./DESIGN.md).

## Architecture Overview

```mermaid
graph TD
    subgraph AWS_Nitro_Enclave["AWS Nitro Enclave"]
        direction TB
        UserApp["User Application<br/>- Generates temporary wallet keypair<br/>- Produces attestation report<br/>- Signs UserOperations"]
    end

    subgraph Nova_Platform["Nova Platform (Off-Chain)"]
        direction TB
        PlatformLogic["- Obtains attestation from enclave<br/>- Generates ZK proof via coprocessor<br/>- Calls on-chain contracts<br/>- Monitors heartbeat"]
    end

    subgraph On_Chain["On-Chain Contracts (Base Sepolia)"]
        direction TB
        NovaRegistry["NovaRegistry<br/>(UUPS Proxy)<br/>← Verifies ZK proofs<br/>← Manages app lifecycle<br/>← Tracks gas budgets"]
        AppWalletFactory["AppWalletFactory<br/>(Deploys EIP-4337 wallets)"]
        NovaPaymaster["NovaPaymaster<br/>(Sponsors gas for apps)"]
        
        AppContract["App Contract<br/>(INovaApp)"]
        AppWallet["AppWallet<br/>(EIP-4337)"]
    end

    UserApp -->|Attestation Report| PlatformLogic
    PlatformLogic -->|ZK Proof + Attestation| NovaRegistry
    
    NovaRegistry --> AppWalletFactory
    NovaRegistry --> NovaPaymaster
    
    AppWalletFactory -->|Deploys| AppWallet
    AppWallet -->|Controls| AppContract
    NovaPaymaster -.->|Sponsors| AppWallet
```

## App Registration Flow

```mermaid
sequenceDiagram
    participant Developer
    participant AppContract
    participant NovaRegistry

    Developer->>AppContract: deploy
    Developer->>AppContract: initialize (PCRs)
    Developer->>NovaRegistry: registerApp (app, PCRs)
    NovaRegistry->>AppContract: verify publisher
    NovaRegistry->>AppContract: verify novaPlatform
    NovaRegistry-->>Developer: emit AppRegistered
    Note over Developer: [Status: Registered]
```

## App Activation Flow

```mermaid
sequenceDiagram
    participant Platform
    participant Enclave
    participant ZKProver
    participant NovaRegistry
    participant AppWalletFactory
    participant AppContract

    Note over Platform, Enclave: Step 1: Deploy App
    Platform->>Enclave: Deploy app to Enclave
    
    Note over Enclave: Step 2: Enclave Logic
    Note right of Enclave: - App running<br/>- Generate wallet<br/>- Generate nonce<br/>- Produce attestation

    Enclave-->>Platform: Step 3: Retrieve attestation<br/>(ETH addr, TLS pubkey, nonce, PCRs, timestamp, signatures)

    Note over Platform, ZKProver: Step 4: ZK Proof Generation
    Platform->>ZKProver: Send attestation
    Note right of ZKProver: - Verify signature<br/>- Extract data
    ZKProver-->>Platform: Return proof + journal

    Note over Platform, NovaRegistry: Step 5: Activation Call
    Platform->>NovaRegistry: activateApp(output, zkCoprocessor, proof)

    Note over NovaRegistry: Step 6.1: Verify Proof
    NovaRegistry->>NovaRegistry: Verify proof & Return journal

    Note over NovaRegistry: Step 6.2: Validate & Consume
    Note right of NovaRegistry: - Check timestamp freshness<br/>- Check attestation not used<br/>- Check nonce not used<br/>- Mark both as consumed<br/>- Extract & Validate PCRs

    Note over NovaRegistry, AppWalletFactory: Step 6.3: Deploy Wallet
    NovaRegistry->>AppWalletFactory: Deploy wallet
    AppWalletFactory-->>NovaRegistry: wallet address
    NovaRegistry->>AppContract: setOperator(ETH addr)

    Note over NovaRegistry: Step 6.4: Finalize
    Note right of NovaRegistry: Update status to Active
    NovaRegistry-->>Platform: emit AppActivated(appContract, operator, wallet)
    
    Note over Platform: [Status: Active, gas-free operations enabled]
```

## UserOperation Execution Flow

```mermaid
sequenceDiagram
    participant Operator
    participant AppWallet
    participant EntryPoint
    participant Paymaster
    participant NovaRegistry

    Operator->>EntryPoint: sign UserOp
    EntryPoint->>AppWallet: validate signature
    EntryPoint->>Paymaster: validate paymaster
    Paymaster->>NovaRegistry: get app instance
    NovaRegistry-->>Paymaster: check budget
    Paymaster-->>EntryPoint: accept
    EntryPoint->>AppWallet: execute
    AppWallet->>Operator: business logic execution
    EntryPoint->>Paymaster: postOp
    Paymaster->>NovaRegistry: deductGas
    Note over NovaRegistry: [Gas deducted from budget]
```

## Trust Boundaries

```mermaid
graph TD
    subgraph Trusted["Trusted Components"]
        Nitro["AWS Nitro Enclave hardware"]
        ZK["ZK Verifier contract"]
        EntryPoint["EIP-4337 EntryPoint"]
    end

    subgraph SemiTrusted["Semi-Trusted Components"]
        Platform["Nova Platform (PLATFORM_ROLE)<br/>Can: Activate apps, heartbeat<br/>Cannot: Modify app data, steal funds"]
    end

    subgraph Untrusted["Untrusted Components"]
        Devs["App developers"]
        Ops["App operators"]
        Users["General users"]
    end
    
    style Trusted fill:#d4edda,stroke:#28a745,stroke-width:2px
    style SemiTrusted fill:#fff3cd,stroke:#ffc107,stroke-width:2px
    style Untrusted fill:#f8d7da,stroke:#dc3545,stroke-width:2px
```

## Deployment Topology

```mermaid
graph TD
    subgraph Governance["Governance Layer"]
        Safe["Gnosis Safe (Multi-sig)"]
        Timelock["Timelock Controller"]
    end

    subgraph OnChain["On-Chain Contracts (Base Mainnet)"]
        Registry["NovaRegistry (UUPS Proxy)"]
        Factory["AppWalletFactory"]
        Paymaster["NovaPaymaster"]
    end

    subgraph PlatformServices["Platform Services"]
        AVS["Attestation Verification Service"]
        Monitor["Heartbeat Monitor"]
        Prover["ZK Proof Generator"]
        Indexer["Event Indexer"]
    end

    subgraph AWS["AWS Infrastructure"]
        EC2["EC2 Instances with Nitro Enclaves"]
        KMS["KMS for key management"]
        CloudWatch["CloudWatch for monitoring"]
    end

    Governance -->|Controls| OnChain
    PlatformServices -->|Interacts with| OnChain
    PlatformServices -->|Manages| AWS
```
