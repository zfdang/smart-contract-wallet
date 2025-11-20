# Nova TEE Platform - Deployment Guide

## Table of Contents

- [Prerequisites](#prerequisites)
- [Environment Setup](#environment-setup)
- [Deployment Steps](#deployment-steps)
- [Post-Deployment Configuration](#post-deployment-configuration)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Tools

- **Foundry**: Latest version ([installation guide](https://book.getfoundry.sh/getting-started/installation))
- **Git**: For cloning the repository
- **Node.js** (optional): For additional scripting

### Required Information

1. **Base Sepolia RPC URL**: Get from [Alchemy](https://www.alchemy.com/) or [Infura](https://infura.io/)
2. **BaseScan API Key**: Register at [BaseScan](https://basescan.org/)
3. **Deployer Private Key**: Wallet with Base Sepolia ETH
4. **Nitro Verifier Address**: Pre-deployed verifier contract address

### Get Test ETH

Request test ETH from Base Sepolia faucets:
- [Coinbase Faucet](https://www.coinbase.com/faucets/base-ethereum-goerli-faucet)
- [Alchemy Faucet](https://sepoliafaucet.com/)

Minimum required: ~0.5 ETH for deployment

## Environment Setup

### 1. Clone Repository

```bash
git clone <repository-url>
cd smart-contract-wallet
```

### 2. Install Dependencies

```bash
# Install OpenZeppelin contracts
forge install OpenZeppelin/openzeppelin-contracts-upgradeable --no-commit
forge install OpenZeppelin/openzeppelin-contracts --no-commit

# Verify installation
forge build
```

### 3. Configure Environment

Create `.env` file in project root:

```bash
# Base Sepolia Network
BASE_SEPOLIA_RPC_URL=https://base-sepolia.g.alchemy.com/v2/YOUR_API_KEY

# Deployment Wallet
PRIVATE_KEY=0x...your_private_key_here...

# Block Explorer
BASESCAN_API_KEY=YOUR_BASESCAN_API_KEY

# External Contracts (update after deployment or with known addresses)
NITRO_VERIFIER_ADDRESS=0x...
ENTRYPOINT_ADDRESS=0x0000000071727De22E5E9d8BAf0edAc6f37da032  # Official AA EntryPoint v0.7
```

> **⚠️ Security Warning**: Never commit `.env` file. Add it to `.gitignore`.

### 4. Load Environment

```bash
source .env
```

## Deployment Steps

### Step 1: Deploy Nitro Verifier (If Not Already Deployed)

If you don't have a Nitro Enclave verifier contract, deploy it first:

```bash
# This is a placeholder - use your actual verifier deployment command
# The verifier contract is outside the scope of this project
```

Update `NITRO_VERIFIER_ADDRESS` in `.env` file.

### Step 2: Deploy NovaRegistry Implementation

Deploy the implementation contract (pre-upgrade):

```bash
forge create nova-contracts/core/NovaRegistry.sol:NovaRegistry \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --verify \
    --etherscan-api-key $BASESCAN_API_KEY
```

Save the deployed address as `NOVA_REGISTRY_IMPL`.

### Step 3: Deploy UUPS Proxy

Deploy the proxy contract:

```bash
# Using OpenZeppelin's ERC1967Proxy
forge create lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --constructor-args $NOVA_REGISTRY_IMPL 0x \
    --verify \
    --etherscan-api-key $BASESCAN_API_KEY
```

Save the deployed address as `NOVA_REGISTRY_PROXY`.

### Step 4: Initialize NovaRegistry

Prepare initialization data:

```bash
# Get your deployer address
DEPLOYER_ADDRESS=$(cast wallet address --private-key $PRIVATE_KEY)

# Encode initialize function call
INIT_DATA=$(cast abi-encode "initialize(address,address,address)" \
    $NITRO_VERIFIER_ADDRESS \
    $DEPLOYER_ADDRESS \
    $DEPLOYER_ADDRESS)

# Call initialize through proxy
cast send $NOVA_REGISTRY_PROXY \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    $INIT_DATA
```

### Step 5: Deploy AppWalletFactory

```bash
forge create nova-contracts/core/AppWalletFactory.sol:AppWalletFactory \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --constructor-args $ENTRYPOINT_ADDRESS $NOVA_REGISTRY_PROXY \
    --verify \
    --etherscan-api-key $BASESCAN_API_KEY
```

Save the deployed address as `APP_WALLET_FACTORY`.

### Step 6: Deploy NovaPaymaster

```bash
forge create nova-contracts/core/NovaPaymaster.sol:NovaPaymaster \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --constructor-args $ENTRYPOINT_ADDRESS $NOVA_REGISTRY_PROXY $DEPLOYER_ADDRESS \
    --verify \
    --etherscan-api-key $BASESCAN_API_KEY
```

Save the deployed address as `NOVA_PAYMASTER`.

### Step 7: Deploy Example App (Optional)

Deploy a test app contract:

```bash
forge create app-contracts/examples/ExampleApp.sol:ExampleApp \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --constructor-args $DEPLOYER_ADDRESS $NOVA_REGISTRY_PROXY \
    --verify \
    --etherscan-api-key $BASESCAN_API_KEY
```

Save the deployed address as `EXAMPLE_APP`.

## Post-Deployment Configuration

### 1. Grant Paymaster Role

```bash
# Get PAYMASTER_ROLE hash
PAYMASTER_ROLE=$(cast keccak "PAYMASTER_ROLE")

# Grant role to NovaPaymaster
cast send $NOVA_REGISTRY_PROXY \
    "grantRole(bytes32,address)" \
    $PAYMASTER_ROLE \
    $NOVA_PAYMASTER \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY
```

### 2. Fund Paymaster

The Paymaster needs ETH deposited in the EntryPoint:

```bash
# Deposit 0.1 ETH to Paymaster's EntryPoint balance
cast send $NOVA_PAYMASTER \
    "deposit()" \
    --value 0.1ether \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY
```

### 3. Configure Heartbeat (Optional)

```bash
# Set heartbeat interval to 30 minutes and expiry to 12 hours (in seconds)
cast send $NOVA_REGISTRY_PROXY \
    "setHeartbeatConfig(uint256,uint256)" \
    1800 \  # 30 minutes
    43200 \ # 12 hours
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY
```

### 4. Initialize Example App (If Deployed)

```bash
# Initialize with test PCR values
cast send $EXAMPLE_APP \
    "initialize(bytes32,bytes32,bytes32)" \
    0x0000000000000000000000000000000000000000000000000000000000000001 \
    0x0000000000000000000000000000000000000000000000000000000000000002 \
    0x0000000000000000000000000000000000000000000000000000000000000003 \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY
```

## Verification

### Verify Deployment

Check that all contracts are deployed and initialized:

```bash
# Check NovaRegistry is initialized
cast call $NOVA_REGISTRY_PROXY "verifier()(address)" --rpc-url $BASE_SEPOLIA_RPC_URL
# Should return: NITRO_VERIFIER_ADDRESS

# Check NovaRegistry has correct roles
cast call $NOVA_REGISTRY_PROXY \
    "hasRole(bytes32,address)(bool)" \
    $(cast keccak "ADMIN_ROLE") \
    $DEPLOYER_ADDRESS \
    --rpc-url $BASE_SEPOLIA_RPC_URL
# Should return: true

# Check Paymaster has role
cast call $NOVA_REGISTRY_PROXY \
    "hasRole(bytes32,address)(bool)" \
    $(cast keccak "PAYMASTER_ROLE") \
    $NOVA_PAYMASTER \
    --rpc-url $BASE_SEPOLIA_RPC_URL
# Should return: true

# Check Paymaster balance in EntryPoint
cast call $ENTRYPOINT_ADDRESS \
    "balanceOf(address)(uint256)" \
    $NOVA_PAYMASTER \
    --rpc-url $BASE_SEPOLIA_RPC_URL
# Should return: >0 (in wei)
```

### Test App Registration

```bash
# Register example app
cast send $NOVA_REGISTRY_PROXY \
    "registerApp(address,bytes32,bytes32,bytes32)" \
    $EXAMPLE_APP \
    0x0000000000000000000000000000000000000000000000000000000000000001 \
    0x0000000000000000000000000000000000000000000000000000000000000002 \
    0x0000000000000000000000000000000000000000000000000000000000000003 \
    --rpc-url $BASE_SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY

# Verify registration
cast call $NOVA_REGISTRY_PROXY \
    "getAppInstance(address)((bytes32,address,address,address,uint256,uint8,uint256,uint256,uint256,uint256))" \
    $EXAMPLE_APP \
    --rpc-url $BASE_SEPOLIA_RPC_URL
```

## Deployment Summary

After successful deployment, save these addresses:

```bash
echo "=== Nova TEE Platform Deployment Summary ==="
echo "Network: Base Sepolia"
echo ""
echo "Core Contracts:"
echo "  NovaRegistry (Proxy): $NOVA_REGISTRY_PROXY"
echo "  NovaRegistry (Impl):  $NOVA_REGISTRY_IMPL"
echo "  AppWalletFactory:     $APP_WALLET_FACTORY"
echo "  NovaPaymaster:        $NOVA_PAYMASTER"
echo ""
echo "External Contracts:"
echo "  NitroVerifier:        $NITRO_VERIFIER_ADDRESS"
echo "  EntryPoint:           $ENTRYPOINT_ADDRESS"
echo ""
echo "Example App:            $EXAMPLE_APP"
```

## Troubleshooting

### Deployment Fails

**Error**: `insufficient funds for gas * price + value`

**Solution**: Get more test ETH from faucet

---

**Error**: `contract creation code storage out of gas`

**Solution**: Use `--legacy` flag for forge create

---

**Error**: `verifier contract not found`

**Solution**: Ensure NITRO_VERIFIER_ADDRESS is correct and deployed

### Initialization Fails

**Error**: `function cannot be called`

**Solution**: Ensure you're calling the proxy address, not implementation

---

**Error**: `Initializable: contract is already initialized`

**Solution**: Contract already initialized, skip this step

### Role Grant Fails

**Error**: `AccessControl: sender must be an admin`

**Solution**: Ensure deployer address has DEFAULT_ADMIN_ROLE

### App Registration Fails

**Error**: `Unauthorized`

**Solution**: Ensure you're calling from the publisher address

---

**Error**: `InvalidAppContract`

**Solution**: Verify app contract implements INovaApp interface

---

**Error**: `AppAlreadyRegistered`

**Solution**: App already registered, use a different address or continue

## Next Steps

After deployment:

1. **Update Platform Backend**: Configure backend with deployed contract addresses
2. **Deploy Sample Enclave**: Test end-to-end flow with a real enclave
3. **Monitor Events**: Set up event monitoring for app lifecycle
4. **Document Addresses**: Save all addresses in a secure location
5. **Set Up Monitoring**: Configure block explorer alerts for critical events

## Production Deployment

For production deployment on Base mainnet:

1. **Use Multi-Sig Wallet**: Deploy with Gnosis Safe as admin
2. **Add Timelock**: Implement timelock for upgrades
3. **Audit Contracts**: Complete third-party security audit
4. **Test Thoroughly**: Extensive testing on testnet first
5. **Budget Planning**: Ensure sufficient funding for operations
6. **Monitoring Setup**: Real-time monitoring and alerting
7. **Incident Response**: Have emergency procedures ready

## Support

For deployment issues:
- Check [GitHub Issues](link-to-issues)
- Review [ARCHITECTURE.md](ARCHITECTURE.md) for system design
- Join community Discord/Telegram

---

**Last Updated**: 2025-11-20  
**Network**: Base Sepolia Testnet  
**Foundry Version**: Latest
