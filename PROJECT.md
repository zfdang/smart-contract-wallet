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
├── interfaces/
│   ├── INovaRegistry.sol      # Registry interface
│   ├── INitroEnclaveVerifier.sol  # Verifier interface
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

### Nova Platform Contracts (9 files)

**Core Platform (3)**:
- [NovaRegistry.sol](file:///home/ubuntu/smart-contract-wallet/nova-contracts/core/NovaRegistry.sol) - Main platform contract
- [AppWalletFactory.sol](file:///home/ubuntu/smart-contract-wallet/nova-contracts/core/AppWalletFactory.sol) - Wallet factory
- [NovaPaymaster.sol](file:///home/ubuntu/smart-contract-wallet/nova-contracts/core/NovaPaymaster.sol) - Gas sponsorship

**Account Abstraction (1)**:
- [AppWallet.sol](file:///home/ubuntu/smart-contract-wallet/nova-contracts/account/AppWallet.sol) - EIP-4337 wallet

**Interfaces (3)**:
- [INovaRegistry.sol](file:///home/ubuntu/smart-contract-wallet/nova-contracts/interfaces/INovaRegistry.sol)
- [INitroEnclaveVerifier.sol](file:///home/ubuntu/smart-contract-wallet/nova-contracts/interfaces/INitroEnclaveVerifier.sol)
- [IEntryPoint.sol](file:///home/ubuntu/smart-contract-wallet/nova-contracts/interfaces/IEntryPoint.sol)

**Libraries & Types (2)**:
- [AttestationLib.sol](file:///home/ubuntu/smart-contract-wallet/nova-contracts/libraries/AttestationLib.sol)
- [NitroTypes.sol](file:///home/ubuntu/smart-contract-wallet/nova-contracts/types/NitroTypes.sol)

### App Contracts (2 files)

**Interfaces (1)**:
- [INovaApp.sol](file:///home/ubuntu/smart-contract-wallet/app-contracts/interfaces/INovaApp.sol) - Standard app interface

**Examples (1)**:
- [ExampleApp.sol](file:///home/ubuntu/smart-contract-wallet/app-contracts/examples/ExampleApp.sol) - Reference implementation

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

## Next Steps

1. **Remove Old Directory**: Delete `contracts-old/` after verification
2. **Update Documentation**: Update README.md with new structure
3. **Update Tests**: Organize tests into `test/nova/` and `test/apps/`
4. **Package Configuration**: Consider splitting into separate packages

---

**Last Updated**: 2025-11-20  
**Structure Version**: 2.0
