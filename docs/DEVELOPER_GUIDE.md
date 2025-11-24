# Nova TEE Platform - Developer Guide

**Version**: 1.0  
**Last Updated**: 2025-11-24

---

## Table of Contents

1. [Introduction](#introduction)
2. [Prerequisites](#prerequisites)
3. [Step 1: Develop Your App](#step-1-develop-your-app)
4. [Step 2: Build TEE Enclave](#step-2-build-tee-enclave)
5. [Step 3: Extract PCRs](#step-3-extract-pcrs)
6. [Step 4: Deploy Smart Contract](#step-4-deploy-smart-contract)
7. [Step 5: Register App](#step-5-register-app)
8. [Step 6: Fund Gas Budget](#step-6-fund-gas-budget)
9. [Step 7: Activate App](#step-7-activate-app)
10. [Step 8: Deploy Wallet (Optional)](#step-8-deploy-wallet-optional)
11. [Step 9: Monitor & Maintain](#step-9-monitor--maintain)
12. [Step 10: Upgrade Your App](#step-10-upgrade-your-app)
13. [Best Practices](#best-practices)
14. [Troubleshooting](#troubleshooting)
15. [API Reference](#api-reference)

---

## Introduction

Welcome to the Nova TEE Platform! This guide walks you through the complete lifecycle of building, deploying, and maintaining a TEE-enabled decentralized application.

### What You'll Build

A **Nova App** consists of:
1. **Smart Contract** - On-chain contract implementing `INovaApp`
2. **TEE Enclave** - Trusted execution environment running your app logic
3. **EIP-4337 Wallet** - Account Abstraction wallet for gas-free operations

### Key Concepts

- **PCRs (Platform Configuration Registers)**: Cryptographic measurements of your enclave code
- **appId**: Unique identifier derived from PCRs: `keccak256(pcr0, pcr1, pcr2)`
- **Attestation**: Cryptographic proof that your code is running in a valid TEE
- **Semantic Versioning**: Track app versions (e.g., "v1.2.3")
- **Version Chains**: Link app versions together to maintain budget continuity

---

## Prerequisites

### Required Tools

```bash
# Development
- Solidity ^0.8.24
- Foundry (forge, cast)
- Node.js >= 18
- Docker

# TEE Environment (choose one)
- AWS Nitro CLI (for AWS Nitro Enclaves)
- Intel SGX SDK (for Intel SGX)
- AMD SEV tools (for AMD SEV-SNP)

# Blockchain
- Ethereum wallet with ETH
- RPC endpoint (Alchemy, Infura, or local node)
```

### Install Dependencies

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Clone Nova contracts (if not already done)
git clone https://github.com/your-org/nova-contracts.git
cd nova-contracts
forge install
```

### Environment Setup

Create `.env` file:
```bash
# Ethereum
PRIVATE_KEY=0x...
RPC_URL=https://eth-mainnet.alchemyapi.io/v2/YOUR_KEY

# Nova Platform
NOVA_REGISTRY_ADDRESS=0x...
NOVA_PLATFORM_ADDRESS=0x...

# TEE Configuration
TEE_TYPE=NitroEnclave  # or IntelSGX, AMDSEV
```

---

## Step 1: Develop Your App

### 1.1 Create App Contract

Your contract must implement `INovaApp`:

```solidity
// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {INovaApp} from "../interfaces/INovaApp.sol";

contract MyNovaApp is INovaApp {
    // Required state variables
    address public immutable publisher;
    address public novaPlatform;
    bytes32 public pcr0;
    bytes32 public pcr1;
    bytes32 public pcr2;

    // Your app state
    mapping(address => uint256) public userBalances;

    constructor(address _publisher, address _novaPlatform) {
        publisher = _publisher;
        novaPlatform = _novaPlatform;
    }

    /// @inheritdoc INovaApp
    function initialize(
        bytes32 _pcr0,
        bytes32 _pcr1,
        bytes32 _pcr2
    ) external override {
        require(msg.sender == publisher, "Only publisher");
        require(pcr0 == bytes32(0), "Already initialized");
        
        pcr0 = _pcr0;
        pcr1 = _pcr1;
        pcr2 = _pcr2;
    }

    /// @inheritdoc INovaApp
    function updatePlatform(address _novaPlatform) external override {
        require(msg.sender == publisher, "Only publisher");
        novaPlatform = _novaPlatform;
    }

    // Your app logic
    function deposit() external payable {
        userBalances[msg.sender] += msg.value;
    }

    function withdraw(uint256 amount) external {
        require(userBalances[msg.sender] >= amount, "Insufficient balance");
        userBalances[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
    }
}
```

### 1.2 Write Tests

```solidity
// test/MyNovaApp.t.sol
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MyNovaApp.sol";

contract MyNovaAppTest is Test {
    MyNovaApp public app;
    address publisher = address(0x1);
    address platform = address(0x2);

    function setUp() public {
        app = new MyNovaApp(publisher, platform);
    }

    function testInitialize() public {
        bytes32 pcr0 = keccak256("PCR0");
        bytes32 pcr1 = keccak256("PCR1");
        bytes32 pcr2 = keccak256("PCR2");

        vm.prank(publisher);
        app.initialize(pcr0, pcr1, pcr2);

        assertEq(app.pcr0(), pcr0);
        assertEq(app.pcr1(), pcr1);
        assertEq(app.pcr2(), pcr2);
    }

    function testDeposit() public {
        vm.deal(address(this), 10 ether);
        app.deposit{value: 1 ether}();
        assertEq(app.userBalances(address(this)), 1 ether);
    }
}
```

Run tests:
```bash
forge test -vv
```

---

## Step 2: Build TEE Enclave

### 2.1 Write Enclave Application

Example enclave structure:
```
my-enclave/
├── Dockerfile.enclave
├── app/
│   ├── main.rs              # Enclave entry point
│   ├── crypto.rs            # Key generation
│   └── attestation.rs       # Attestation generation
├── Cargo.toml
└── build.sh
```

**Sample Rust Entry Point**:
```rust
// app/main.rs
use std::net::TcpListener;
use ethers::signers::{LocalWallet, Signer};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Generate ephemeral operator key inside enclave
    let wallet = LocalWallet::new(&mut rand::thread_rng());
    let operator_address = wallet.address();
    
    println!("Operator address: {:?}", operator_address);
    
    // Start HTTP server for operations
    let listener = TcpListener::bind("0.0.0.0:8080")?;
    println!("Enclave listening on port 8080");
    
    for stream in listener.incoming() {
        match stream {
            Ok(stream) => handle_request(stream, &wallet).await?,
            Err(e) => eprintln!("Connection failed: {}", e),
        }
    }
    
    Ok(())
}

async fn handle_request(
    stream: TcpStream,
    wallet: &LocalWallet
) -> Result<(), Box<dyn std::error::Error>> {
    // Handle RPC requests
    // Sign transactions
    // Return attestations
    Ok(())
}
```

### 2.2 Build Enclave Image

**Dockerfile.enclave** (AWS Nitro):
```dockerfile
FROM amazon/aws-nitro-enclaves-sdk-c:latest

WORKDIR /app
COPY . .

# Build Rust application
RUN cargo build --release

# Set entrypoint
CMD ["/app/target/release/my-enclave"]
```

**Build Script**:
```bash
#!/bin/bash
# build.sh

# Build Docker image
docker build -f Dockerfile.enclave -t my-enclave:latest .

# Convert to enclave image format (Nitro)
nitro-cli build-enclave \
    --docker-uri my-enclave:latest \
    --output-file my-enclave.eif

echo "Enclave image built: my-enclave.eif"
```

Run build:
```bash
chmod +x build.sh
./build.sh
```

---

## Step 3: Extract PCRs

### 3.1 Get PCR Values

**For AWS Nitro Enclaves**:
```bash
# PCRs are output during build
nitro-cli build-enclave \
    --docker-uri my-enclave:latest \
    --output-file my-enclave.eif

# Output includes:
# PCR0: 0x1234...  (Enclave image hash)
# PCR1: 0x5678...  (Kernel/OS hash)
# PCR2: 0x9abc...  (Application hash)
```

**For Intel SGX**:
```bash
# Extract MRENCLAVE and MRSIGNER
sgx_sign dump -enclave my-enclave.so -dumpfile metadata.txt
cat metadata.txt | grep -E "MRENCLAVE|MRSIGNER"
```

### 3.2 Save PCR Values

Create `pcrs.json`:
```json
{
  "pcr0": "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
  "pcr1": "0x5678901234abcdef5678901234abcdef5678901234abcdef5678901234abcdef",
  "pcr2": "0x9abcdef1234567909abcdef1234567909abcdef1234567909abcdef123456790",
  "teeType": "NitroEnclave",
  "version": "v1.0.0"
}
```

---

## Step 4: Deploy Smart Contract

### 4.1 Deploy Contract

```bash
# Using Foundry
forge create \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --constructor-args $PUBLISHER_ADDRESS $NOVA_REGISTRY_ADDRESS \
    src/MyNovaApp.sol:MyNovaApp
```

Save the deployed contract address:
```bash
export APP_CONTRACT=0x...  # Your deployed contract address
```

### 4.2 Initialize with PCRs

```bash
# Load PCRs from pcrs.json
PCR0=$(jq -r '.pcr0' pcrs.json)
PCR1=$(jq -r '.pcr1' pcrs.json)
PCR2=$(jq -r '.pcr2' pcrs.json)

# Initialize contract
cast send $APP_CONTRACT \
    "initialize(bytes32,bytes32,bytes32)" \
    $PCR0 $PCR1 $PCR2 \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY
```

### 4.3 Verify Initialization

```bash
cast call $APP_CONTRACT "pcr0()(bytes32)" --rpc-url $RPC_URL
cast call $APP_CONTRACT "pcr1()(bytes32)" --rpc-url $RPC_URL
cast call $APP_CONTRACT "pcr2()(bytes32)" --rpc-url $RPC_URL
```

---

## Step 5: Register App

### 5.1 First-Time Registration

For your first version (v1.0.0):

```bash
# Register with version information
cast send $NOVA_REGISTRY_ADDRESS \
    "registerApp(address,bytes32,bytes32,bytes32,bytes32,string)" \
    $APP_CONTRACT \
    $PCR0 \
    $PCR1 \
    $PCR2 \
    0x0000000000000000000000000000000000000000000000000000000000000000 \
    "v1.0.0" \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY
```

**Parameters**:
- `address appContract`: Your deployed contract
- `bytes32 pcr0, pcr1, pcr2`: PCR values
- `bytes32 previousAppId`: `0x0` for first version
- `string semanticVersion`: "v1.0.0"

### 5.2 Verify Registration

```bash
# Get app instance details
cast call $NOVA_REGISTRY_ADDRESS \
    "getAppInstance(address)((bytes32,address,address,address,uint256,uint8,uint256,uint256,uint256,uint256,uint8))" \
    $APP_CONTRACT \
    --rpc-url $RPC_URL

# Check version history
cast call $NOVA_REGISTRY_ADDRESS \
    "getVersionHistory(address)(bytes32[])" \
    $APP_CONTRACT \
    --rpc-url $RPC_URL
```

---

## Step 6: Fund Gas Budget

### 6.1 Add Funds

```bash
# Fund with 1 ETH for gas budget
cast send $NOVA_REGISTRY_ADDRESS \
    "fundApp(address)" \
    $APP_CONTRACT \
    --value 1ether \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY
```

### 6.2 Check Budget

```bash
# Query current gas budget
cast call $NOVA_REGISTRY_ADDRESS \
    "getAppInstance(address)" \
    $APP_CONTRACT \
    --rpc-url $RPC_URL | jq '.gasBudget'
```

### 6.3 Top Up Budget

You can add more funds anytime:

```bash
# Add another 0.5 ETH
cast send $NOVA_REGISTRY_ADDRESS \
    "fundApp(address)" \
    $APP_CONTRACT \
    --value 0.5ether \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY
```

---

## Step 7: Activate App

### 7.1 Deploy Enclave

**On AWS Nitro**:
```bash
# Run enclave
nitro-cli run-enclave \
    --eif-path my-enclave.eif \
    --memory 2048 \
    --cpu-count 2 \
    --enclave-cid 16

# Verify enclave is running
nitro-cli describe-enclaves
```

### 7.2 Generate Attestation

Request attestation from your enclave:
```bash
# HTTP request to enclave
curl http://localhost:8080/attestation \
    -d '{"appContract": "'$APP_CONTRACT'"}' \
    > attestation.bin
```

### 7.3 Generate ZK Proof

Submit attestation to Nova Platform for ZK proof generation:
```bash
# Platform generates proof (10-60 seconds)
curl https://platform.nova.io/generate-proof \
    -H "Authorization: Bearer $API_KEY" \
    -F "attestation=@attestation.bin" \
    -F "appContract=$APP_CONTRACT" \
    > proof.bin
```

### 7.4 Submit Activation

The Nova Platform will automatically submit the activation transaction:

```bash
# Platform calls activateApp()
cast send $NOVA_REGISTRY_ADDRESS \
    "activateApp(address,uint8,bytes,bytes)" \
    $APP_CONTRACT \
    0 \
    $(cat attestation.bin | xxd -p | tr -d '\n') \
    $(cat proof.bin | xxd -p | tr -d '\n') \
    --rpc-url $RPC_URL \
    --private-key $PLATFORM_PRIVATE_KEY
```

### 7.5 Verify Activation

```bash
# Check status
cast call $NOVA_REGISTRY_ADDRESS \
    "getAppInstance(address)" \
    $APP_CONTRACT \
    --rpc-url $RPC_URL

# Look for:
# - status: 1 (Active)
# - operator: 0x... (your enclave's operator address)
# - walletAddress: 0x... (initially = operator)
```

---

## Step 8: Deploy Wallet (Optional)

### 8.1 When to Deploy Wallet

Deploy an EIP-4337 wallet if you need:
- Gas-free user operations
- Advanced account abstraction features
- Paymaster-sponsored transactions

### 8.2 Deploy via Factory

```bash
# Platform deploys wallet
WALLET_FACTORY=0x...  # AppWalletFactory address

cast send $WALLET_FACTORY \
    "createWallet(address,address,bytes32)" \
    $APP_CONTRACT \
    $OPERATOR_ADDRESS \
    $(cast keccak $APP_CONTRACT,$OPERATOR_ADDRESS) \
    --rpc-url $RPC_URL \
    --private-key $PLATFORM_PRIVATE_KEY

# Get wallet address
WA LLET=$(cast call $WALLET_FACTORY \
    "getWalletAddress(address,address,bytes32)(address)" \
    $APP_CONTRACT $OPERATOR_ADDRESS $(cast keccak ...) \
    --rpc-url $RPC_URL)
```

### 8.3 Update Wallet Address

```bash
# Platform updates registry
cast send $NOVA_REGISTRY_ADDRESS \
    "updateWalletAddress(address,address)" \
    $APP_CONTRACT \
    $WALLET \
    --rpc-url $RPC_URL \
    --private-key $PLATFORM_PRIVATE_KEY
```

---

## Step 9: Monitor & Maintain

### 9.1 Monitor App Status

```bash
# Check current status
cast call $NOVA_REGISTRY_ADDRESS \
    "getAppInstance(address)" \
    $APP_CONTRACT \
    --rpc-url $RPC_URL

# Monitor events
cast logs \
    --address $NOVA_REGISTRY_ADDRESS \
    --from-block latest \
    --rpc-url $RPC_URL
```

### 9.2 Heartbeat Monitoring

The platform sends heartbeats every hour. Monitor them:

```bash
# Listen for HeartbeatUpdated events
cast logs \
    --address $NOVA_REGISTRY_ADDRESS \
    --event "HeartbeatUpdated(address,uint256)" \
    --from-block -100 \
    --rpc-url $RPC_URL
```

### 9.3 Gas Usage Tracking

```bash
# Check gas consumption
cast call $NOVA_REGISTRY_ADDRESS \
    "getAppInstance(address)" \
    $APP_CONTRACT \
    --rpc-url $RPC_URL | jq '.gasUsed'

# Check remaining budget
cast call $NOVA_REGISTRY_ADDRESS \
    "getAppInstance(address)" \
    $APP_CONTRACT \
    --rpc-url $RPC_URL | jq '.gasBudget'
```

### 9.4 Set Up Alerts

Example monitoring script:
```bash
#!/bin/bash
# monitor.sh

THRESHOLD=0.1  # Alert when budget < 0.1 ETH

while true; do
    BUDGET=$(cast call $NOVA_REGISTRY_ADDRESS \
        "getAppInstance(address)" \
        $APP_CONTRACT \
        --rpc-url $RPC_URL | jq -r '.gasBudget')
    
    BUDGET_ETH=$(bc <<< "scale=4; $BUDGET / 10^18")
    
    if (( $(bc <<< "$BUDGET_ETH < $THRESHOLD") )); then
        echo "⚠️  LOW BUDGET: $BUDGET_ETH ETH remaining"
        # Send alert (email, Slack, etc.)
    fi
    
    sleep 3600  # Check every hour
done
```

---

## Step 10: Upgrade Your App

### 10.1 When to Upgrade

Upgrade scenarios:
- **Patch (v1.0.0 → v1.0.1)**: Bug fixes, log updates
- **Minor (v1.0.0 → v1.1.0)**: New features, backward compatible
- **Major (v1.0.0 → v2.0.0)**: Breaking changes

### 10.2 Build New Version

```bash
# 1. Update code
vim src/MyNovaApp.sol

# 2. Rebuild enclave
./build.sh

# 3. Extract new PCRs
nitro-cli build-enclave ... > build-output.txt
NEW_PCR0=$(grep "PCR0" build-output.txt | awk '{print $2}')
NEW_PCR1=$(grep "PCR1" build-output.txt | awk '{print $2}')
NEW_PCR2=$(grep "PCR2" build-output.txt | awk '{print $2}')

# 4. Save PCRs
cat > pcrs-v1.0.1.json <<EOF
{
  "pcr0": "$NEW_PCR0",
  "pcr1": "$NEW_PCR1",
  "pcr2": "$NEW_PCR2",
  "version": "v1.0.1"
}
EOF
```

### 10.3 Deploy New Contract

```bash
# Deploy new contract version
forge create \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --constructor-args $PUBLISHER_ADDRESS $NOVA_REGISTRY_ADDRESS \
    src/MyNovaApp.sol:MyNovaApp

NEW_APP_CONTRACT=0x...  # Save new address

# Initialize with new PCRs
cast send $NEW_APP_CONTRACT \
    "initialize(bytes32,bytes32,bytes32)" \
    $NEW_PCR0 $NEW_PCR1 $NEW_PCR2 \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY
```

### 10.4 Register New Version

```bash
# Calculate old appId
OLD_APP_ID=$(cast keccak \
    $(cast abi-encode "f(bytes32,bytes32,bytes32)" $PCR0 $PCR1 $PCR2))

# Register new version linked to old
cast send $NOVA_REGISTRY_ADDRESS \
    "registerApp(address,bytes32,bytes32,bytes32,bytes32,string)" \
    $NEW_APP_CONTRACT \
    $NEW_PCR0 \
    $NEW_PCR1 \
    $NEW_PCR2 \
    $OLD_APP_ID \
    "v1.0.1" \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY
```

### 10.5 Migrate Budget

```bash
# Calculate new appId
NEW_APP_ID=$(cast keccak \
    $(cast abi-encode "f(bytes32,bytes32,bytes32)" $NEW_PCR0 $NEW_PCR1 $NEW_PCR2))

# Migrate budget from old to new version
cast send $NOVA_REGISTRY_ADDRESS \
    "migrateAppBudget(address,bytes32)" \
    $NEW_APP_CONTRACT \
    $NEW_APP_ID \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY

# Verify budget transferred
cast call $NOVA_REGISTRY_ADDRESS \
    "getAppInstance(address)" \
    $NEW_APP_CONTRACT \
    --rpc-url $RPC_URL | jq '.gasBudget'
```

### 10.6 Activate New Version

```bash
# 1. Deploy new enclave
nitro-cli run-enclave --eif-path my-enclave-v1.0.1.eif ...

# 2. Generate attestation
curl http://localhost:8080/attestation > attestation-v1.0.1.bin

# 3. Generate proof and activate
# (Same process as Step 7)
```

### 10.7 Version History

```bash
# View all versions
cast call $NOVA_REGISTRY_ADDRESS \
    "getVersionHistory(address)(bytes32[])" \
    $APP_CONTRACT \
    --rpc-url $RPC_URL

# Get version details
cast call $NOVA_REGISTRY_ADDRESS \
    "getAppVersion(bytes32)((bytes32,bytes32,uint256,string,bool))" \
    $APP_ID \
    --rpc-url $RPC_URL
```

---

## Best Practices

### Development

1. **Reproducible Builds**: Use Docker for deterministic enclave builds
   ```dockerfile
   FROM ubuntu:22.04
   ENV DEBIAN_FRONTEND=noninteractive
   RUN apt-get update && apt-get install -y --no-install-recommends \
       build-essential=12.9ubuntu3
   # Pin all dependencies
   ```

2. **Test Thoroughly**: Test both contract and enclave logic
   ```bash
   # Contract tests
   forge test -vvv
   
   # Enclave integration tests
   cargo test --release
   ```

3. **Document PCRs**: Keep a record of all PCR values per version
   ```
   versions/
   ├── v1.0.0/
   │   ├── pcrs.json
   │   └── my-enclave-v1.0.0.eif
   ├── v1.0.1/
   │   ├── pcrs.json
   │   └── my-enclave-v1.0.1.eif
   ```

### Security

1. **Key Management**: Never expose operator private keys
   - Generate keys inside enclave only
   - Don't log private keys
   - Rotate regularly

2. **Version Validation**: Always verify version chains
   ```bash
   # Verify previousAppId is correct
   OLD_VERSION=$(cast call $NOVA_REGISTRY_ADDRESS \
       "getAppVersion(bytes32)" $OLD_APP_ID --rpc-url $RPC_URL)
   ```

3. **Budget Monitoring**: Set up low-budget alerts
   ```bash
   # Alert when budget < 0.1 ETH
   if [ $BUDGET_ETH < 0.1 ]; then alert; fi
   ```

### Operations

1. **Automated Monitoring**: Use monitoring tools
   ```yaml
   # prometheus.yml
   - job_name: 'nova-app'
     static_configs:
       - targets: ['localhost:9090']
     metrics_path: '/metrics'
   ```

2. **Graceful Upgrades**: Plan upgrade windows
   - Announce upgrade 24h in advance
   - Maintain old version during migration
   - Monitor both versions for 48h

3. **Backup Strategies**: Keep backups of:
   - Contract deployment artifacts
   - Enclave images (.eif files)
   - PCR records
   - Version history

### Cost Optimization

1. **Batch Operations**: Group user operations when possible

2. **Gas Budgeting**:
   ```
   Expected usage: 1000 ops/day × 200k gas = 200M gas/day
   At 50 gwei = 0.01 ETH/day
   Budget for 30 days = 0.3 ETH
   ```

3. **L2 Deployment**: Consider deploying on L2 for 10x cost savings

---

## Troubleshooting

### Contract Deployment Issues

**Problem**: Contract deployment fails
```bash
Error: Insufficient funds
```

**Solution**: Ensure wallet has enough ETH
```bash
cast balance $PUBLISHER_ADDRESS --rpc-url $RPC_URL
# Need gas + constructor value
```

---

**Problem**: Initialize fails with "Already initialized"
```solidity
Error: Already initialized
```

**Solution**: Check current PCRs
```bash
cast call $APP_CONTRACT "pcr0()(bytes32)" --rpc-url $RPC_URL
# If not 0x0, already initialized
```

### Registration Issues

**Problem**: "AppAlreadyRegistered" error

**Solution**: Check if app is registered
```bash
cast call $NOVA_REGISTRY_ADDRESS \
    "getAppInstance(address)" \
    $APP_CONTRACT \
    --rpc-url $RPC_URL
```

---

**Problem**: "InvalidVersionChain" error

**Solution**: Verify previousAppId
```bash
# Check version history
cast call $NOVA_REGISTRY_ADDRESS \
    "getVersionHistory(address)" \
    $APP_CONTRACT \
    --rpc-url $RPC_URL

# Use the latest appId as previousAppId
```

### Activation Issues

**Problem**: Activation fails with "VerificationFailed"

**Causes**:
1. Incorrect PCRs in contract
2. Attestation from different code
3. Invalid ZK proof

**Solution**:
```bash
# 1. Verify PCRs match
ACTUAL_PCR0=$(nitro-cli describe-enclaves | jq -r '.[0].Measurements.PCR0')
CONTRACT_PCR0=$(cast call $APP_CONTRACT "pcr0()(bytes32)" --rpc-url $RPC_URL)

# Compare
if [ "$ACTUAL_PCR0" != "$CONTRACT_PCR0" ]; then
    echo "PCR mismatch!"
fi

# 2. Regenerate attestation
curl http://localhost:8080/attestation > new-attestation.bin

# 3. Regenerate proof
curl https://platform.nova.io/generate-proof ...
```

---

**Problem**: "AttestationExpired" error

**Solution**: Attestations must be activated within 5 minutes
```bash
# Check attestation timestamp
cast call $NOVA_REGISTRY_ADDRESS \
    "ATTESTATION_VALIDITY_WINDOW()(uint256)" \
    --rpc-url $RPC_URL
# Returns: 300 (5 minutes)

# Generate fresh attestation
curl http://localhost:8080/attestation > fresh-attestation.bin
```

### Budget Issues

**Problem**: "InsufficientGasBudget" error

**Solution**: Add more funds
```bash
# Check current budget
BUDGET=$(cast call $NOVA_REGISTRY_ADDRESS \
    "getAppInstance(address)" $APP_CONTRACT --rpc-url $RPC_URL | jq '.gasBudget')

# Add 1 ETH
cast send $NOVA_REGISTRY_ADDRESS \
    "fundApp(address)" $APP_CONTRACT \
    --value 1ether \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY
```

### Upgrade Issues

**Problem**: Budget migration fails

**Solution**: Verify version chain link
```bash
# Check new version's previousAppId
NEW_VERSION=$(cast call $NOVA_REGISTRY_ADDRESS \
    "getAppVersion(bytes32)" $NEW_APP_ID --rpc-url $RPC_URL)

PREVIOUS_ID=$(echo $NEW_VERSION | jq -r '.previousAppId')
CURRENT_ID=$(cast call $NOVA_REGISTRY_ADDRESS \
    "getAppInstance(address)" $APP_CONTRACT --rpc-url $RPC_URL | jq -r '.appId')

if [ "$PREVIOUS_ID" != "$CURRENT_ID" ]; then
    echo "Version chain broken!"
fi
```

### Monitoring Issues

**Problem**: App shows as "Inactive"

**Cause**: Missed heartbeat (no heartbeat in > heartbeatInterval)

**Solution**:
```bash
# Check last heartbeat
cast call $NOVA_REGISTRY_ADDRESS \
    "getAppInstance(address)" $APP_CONTRACT \
    --rpc-url $RPC_URL | jq '.lastHeartbeat'

# Platform should send heartbeat
# Contact platform support if heartbeats stopped
```

---

## API Reference

### INovaApp Interface

```solidity
interface INovaApp {
    function publisher() external view returns (address);
    function novaPlatform() external view returns (address);
    function pcr0() external view returns (bytes32);
    function pcr1() external view returns (bytes32);
    function pcr2() external view returns (bytes32);
    
    function initialize(bytes32 _pcr0, bytes32 _pcr1, bytes32 _pcr2) external;
    function updatePlatform(address _novaPlatform) external;
}
```

### NovaRegistry Functions

```solidity
// Registration
function registerApp(
    address appContract,
    bytes32 pcr0, bytes32 pcr1, bytes32 pcr2,
    bytes32 previousAppId,
    string calldata semanticVersion
) external;

// Activation (Platform only)
function activateApp(
    address appContract,
    TEEType teeType,
    bytes calldata attestation,
    bytes calldata proof
) external;

// Funding
function fundApp(address appContract) external payable;

// Budget Migration
function migrateAppBudget(address appContract, bytes32 newAppId) external;

// Queries
function getAppInstance(address appContract) external view returns (AppInstance memory);
function getVersionHistory(address appContract) external view returns (bytes32[] memory);
function getAppVersion(bytes32 appId) external view returns (AppVersion memory);
```

### Events

```solidity
event AppRegistered(address indexed appContract, bytes32 indexed appId, bytes32 pcr0, bytes32 pcr1, bytes32 pcr2);
event AppActivated(address indexed appContract, address indexed operator, address walletAddress, uint256 version);
event AppVersionLinked(address indexed appContract, bytes32 indexed newAppId, bytes32 indexed previousAppId, string semanticVersion);
event BudgetMigrated(address indexed appContract, bytes32 indexed fromAppId, bytes32 indexed toAppId, uint256 amount);
event AppFunded(address indexed appContract, address indexed funder, uint256 amount);
event HeartbeatUpdated(address indexed appContract, uint256 timestamp);
```

---

## Additional Resources

- **Nova Platform Documentation**: https://docs.nova.io
- **AWS Nitro Enclaves Guide**: https://docs.aws.amazon.com/enclaves/
- **Intel SGX Developer Guide**: https://software.intel.com/sgx
- **EIP-4337 Specification**: https://eips.ethereum.org/EIPS/eip-4337
- **Foundry Book**: https://book.getfoundry.sh/

## Getting Help

- **Discord**: https://discord.gg/nova
- **Forum**: https://forum.nova.io
- **GitHub Issues**: https://github.com/your-org/nova-contracts/issues
- **Email**: developers@nova.io

---

**Happy Building!** 🚀

If you encounter any issues or have questions, please reach out to our developer community.
