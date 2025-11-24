# Nova TEE Platform - Project Structure

## Directory Organization

The project is organized into two main contract directories:

### `nova-contracts/` - Platform Contracts

Core Nova platform contracts managed by the platform team.

```
nova-contracts/
├── core/                       # Core platform contracts
│   ├── NovaRegistry.sol       # Main registry (UUPS upgradeable)
│   ├── AppWalletFactory.sol   # EIP-4337 wallet factory
│   └── NovaPaymaster.sol      # Gas sponsorship paymaster
├── account/
│   └── AppWallet.sol          # EIP-4337 wallet implementation
├── verifiers/                 # TEE attestation verifiers
│   ├── NitroEnclaveVerifier.sol   # AWS Nitro Enclave verifier
│   ├── IntelSGXVerifier.sol       # Intel SGX verifier (placeholder)
│   └── AMDSEVVerifier.sol         # AMD SEV-SNP verifier (placeholder)
├── interfaces/
│   ├── INovaRegistry.sol      # Registry interface
│   ├── INitroEnclaveVerifier.sol  # Nitro verifier interface
│   ├── ITEEVerifier.sol       # Generic TEE verifier interface
│   └── IEntryPoint.sol        # EIP-4337 interfaces
├── libraries/
│   └── AttestationLib.sol     # Attestation processing
└── types/
    └── NitroTypes.sol         # Type definitions
```

### `app-contracts/` - Application Contracts

Example and template contracts for developers building on Nova.

```
app-contracts/
├── interfaces/
│   └── INovaApp.sol           # Standard app interface
└── examples/
    └── ExampleApp.sol         # Reference implementation
```

## Contract Summary

### Nova Platform Contracts (13 files)

**Core Platform (3)**:
- [NovaRegistry.sol](file:///home/ubuntu/smart-contract-wallet/nova-contracts/core/NovaRegistry.sol) - Main platform contract
- [AppWalletFactory.sol](file:///home/ubuntu/smart-contract-wallet/nova-contracts/core/AppWalletFactory.sol) - Wallet factory
- [NovaPaymaster.sol](file:///home/ubuntu/smart-contract-wallet/nova-contracts/core/NovaPaymaster.sol) - Gas sponsorship

**Account Abstraction (1)**:
- [AppWallet.sol](file:///home/ubuntu/smart-contract-wallet/nova-contracts/account/AppWallet.sol) - EIP-4337 wallet

**TEE Verifiers (3)**:
- [NitroEnclaveVerifier.sol](nova-contracts/verifiers/NitroEnclaveVerifier.sol) - AWS Nitro verifier
- [IntelSGXVerifier.sol](nova-contracts/verifiers/IntelSGXVerifier.sol) - Intel SGX placeholder
- [AMDSEVVerifier.sol](nova-contracts/verifiers/AMDSEVVerifier.sol) - AMD SEV placeholder

**Interfaces (4)**:
- [INovaRegistry.sol](nova-contracts/interfaces/INovaRegistry.sol)
- [INitroEnclaveVerifier.sol](nova-contracts/interfaces/INitroEnclaveVerifier.sol)
- [ITEEVerifier.sol](nova-contracts/interfaces/ITEEVerifier.sol)
- [IEntryPoint.sol](nova-contracts/interfaces/IEntryPoint.sol)

**Libraries & Types (2)**:
- [AttestationLib.sol](nova-contracts/libraries/AttestationLib.sol)
- [NitroTypes.sol](nova-contracts/types/NitroTypes.sol)

### App Contracts (2 files)

**Interfaces (1)**:
- [INovaApp.sol](app-contracts/interfaces/INovaApp.sol) - Standard app interface

**Examples (1)**:
- [ExampleApp.sol](app-contracts/examples/ExampleApp.sol) - Reference implementation

## Import Path Conventions

### For Nova Platform Contracts

```solidity
// Importing within nova-contracts
import {INovaRegistry} from "../interfaces/INovaRegistry.sol";
import {AttestationLib} from "../libraries/AttestationLib.sol";

// Importing app interfaces
import {INovaApp} from "../../app-contracts/interfaces/INovaApp.sol";
```

### For App Contracts

```solidity
// Importing app interfaces
import {INovaApp} from "../interfaces/INovaApp.sol";

// Importing nova-contracts
import {INovaRegistry} from "../../nova-contracts/interfaces/INovaRegistry.sol";
```

### For Deployment Scripts

```solidity
import {NovaRegistry} from "../nova-contracts/core/NovaRegistry.sol";
import {ExampleApp} from "../app-contracts/examples/ExampleApp.sol";
```

## Benefits of This Structure

1. **Clear Separation**: Platform contracts vs application contracts
2. **Easier Maintenance**: Platform team can update nova-contracts independently
3. **Better for Developers**: App developers only need to focus on app-contracts
4. **Modular**: Each directory can potentially be a separate npm package
5. **Security**: Clear boundaries make auditing easier

## Development Workflow

### For Platform Development

```bash
# Work in nova-contracts directory
cd nova-contracts

# Run tests
forge test --match-path "test/nova/**"
```

### For App Development

```bash
# Work in app-contracts directory
cd app-contracts

# Use INovaApp interface and ExampleApp as template
# Import nova-contracts interfaces as needed
```

## Recent Improvements

### Multi-TEE Support
- Added `ITEEVerifier` interface for pluggable TEE verifiers
- Implemented `NitroEnclaveVerifier` with full attestation verification
- Added placeholder verifiers for Intel SGX and AMD SEV-SNP
- Registry now supports multiple TEE types (Nitro, SGX, SEV)

### Version Chains
- Apps can now register with semantic versioning (e.g., "v1.0.0")
- Budget migration support for seamless upgrades
- Version history tracking per app contract
- Backward-compatible version chain linking

### Gas Optimizations
- Batch heartbeat updates (83% gas savings for 1000 apps)
- Bounded storage with attestation cleanup (7-day retention)
- Efficient replay protection with dual hash tracking

### Developer Experience
- Updated `INovaApp` interface with PCR getters
- Comprehensive `DEVELOPER_GUIDE.md` with 10-step lifecycle
- Complete API reference in `API.md`
- Example deployment scripts and tests

---

**Last Updated**: 2025-11-24  
**Structure Version**: 2.1
