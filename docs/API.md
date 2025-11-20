# Nova TEE Platform - API Reference

## Table of Contents

- [NovaRegistry](#novaregistry)
- [AppWalletFactory](#appwalletfactory)
- [NovaPaymaster](#novapaymaster)
- [AppWallet](#appwallet)
- [INovaApp Interface](#inovaapp-interface)

## NovaRegistry

Main platform contract managing app lifecycle and verification.

### Read Functions

#### `getAppInstance(address appContract) → AppInstance`

Get details of an app instance.

**Parameters:**
- `appContract`: Address of the app contract

**Returns:**
- `AppInstance` struct containing app details

**Example:**
```solidity
AppInstance memory instance = novaRegistry.getAppInstance(appContract);
console.log("Status:", instance.status);
console.log("Operator:", instance.operator);
console.log("Gas Budget:", instance.gasBudget);
```

---

#### `getAppMetadata(bytes32 appId) → AppMetadata`

Get metadata for an app group (by PCR hash).

**Parameters:**
- `appId`: App identifier (keccak256(pcr0, pcr1, pcr2))

**Returns:**
- `AppMetadata` struct with PCRs, instance count, latest version

---

#### `getAppsByPCRs(bytes32 pcr0, bytes32 pcr1, bytes32 pcr2) → address[]`

Get all app instances with specific PCRs.

**Parameters:**
- `pcr0`, `pcr1`, `pcr2`: PCR values

**Returns:**
- Array of app contract addresses

**Example:**
```solidity
address[] memory instances = novaRegistry.getAppsByPCRs(pcr0, pcr1, pcr2);
for (uint i = 0; i < instances.length; i++) {
    console.log("Instance:", instances[i]);
}
```

---

#### `heartbeatInterval() → uint256`

Get configured heartbeat interval in seconds.

---

#### `heartbeatExpiry() → uint256`

Get configured heartbeat expiry duration in seconds.

### Write Functions

#### `registerApp(address appContract, bytes32 pcr0, bytes32 pcr1, bytes32 pcr2)`

Register a new app with expected PCR values.

**Access:** Public (must be called by app publisher)

**Parameters:**
- `appContract`: Address of the app contract
- `pcr0`, `pcr1`, `pcr2`: Expected PCR values

**Requirements:**
- Caller must be the app's publisher
- App contract must reference this registry as novaPlatform
- PCRs must not be zero
- App not already registered

**Events:**
- `AppRegistered(appContract, appId, pcr0, pcr1, pcr2)`

**Example:**
```solidity
novaRegistry.registerApp(
    address(myApp),
    0x0001...,
    0x0002...,
    0x0003...
);
```

---

#### `activateApp(address appContract, bytes output, ZkCoProcessorType zkCoprocessor, bytes proofBytes)`

Activate an app after verifying attestation proof.

**Access:** PLATFORM_ROLE only

**Parameters:**
- `appContract`: App contract address
- `output`: Encoded VerifierJournal from attestation
- `zkCoprocessor`: Type of ZK coprocessor used (RiscZero or Succinct)
- `proofBytes`: ZK proof data

**Requirements:**
- App must be registered
- ZK proof must be valid
- PCRs in attestation must match registered values

**Events:**
- `AppActivated(appContract, operator, walletAddress, version)`

---

#### `heartbeat(address appContract)`

Update app's heartbeat timestamp.

**Access:** PLATFORM_ROLE only

**Parameters:**
- `appContract`: App contract address

**Requirements:**
- App must be registered
- App status must be Active or Inactive

**Events:**
- `HeartbeatUpdated(appContract, timestamp)`

**Example:**
```solidity
novaRegistry.heartbeat(appContract);
```

---

#### `updatePCRs(address appContract, bytes32 pcr0, bytes32 pcr1, bytes32 pcr2)`

Update registered PCR values for an app.

**Access:** App contract or publisher

**Parameters:**
- `appContract`: App contract address
- `pcr0`, `pcr1`, `pcr2`: New PCR values

**Requirements:**
- Caller must be app contract or publisher
- PCRs must not be zero

**Events:**
- `PCRsUpdated(appContract, pcr0, pcr1, pcr2)`

---

#### `fundApp(address appContract) payable`

Add funds to an app's gas budget.

**Access:** Public (anyone can fund)

**Parameters:**
- `appContract`: App contract address

**Requirements:**
- App must be registered
- msg.value > 0

**Events:**
- `AppFunded(appContract, funder, amount)`

**Example:**
```solidity
novaRegistry.fundApp{value: 1 ether}(appContract);
```

---

#### `deleteApp(address appContract)`

Delete an app instance.

**Access:** ADMIN_ROLE only

**Parameters:**
- `appContract`: App contract address

**Requirements:**
- App must exist
- Not already deleted

**Events:**
- `AppDeleted(appContract)`

---

#### `checkAndMarkInactive(address[] calldata appContracts)`

Check and mark apps as inactive if heartbeat expired.

**Access:** Public

**Parameters:**
- `appContracts`: Array of app contract addresses to check

**Events:**
- `AppInactive(appContract)` for each app marked inactive

---

#### `deductGas(address appContract, uint256 gasAmount)`

Deduct gas from app's budget (called by Paymaster).

**Access:** PAYMASTER_ROLE only

**Parameters:**
- `appContract`: App contract address
- `gasAmount`: Amount of gas to deduct (in wei)

**Requirements:**
- Sufficient gas budget

**Events:**
- `GasConsumed(appContract, amount)`

### Admin Functions

#### `setHeartbeatConfig(uint256 interval, uint256 expiry)`

Configure heartbeat parameters.

**Access:** ADMIN_ROLE only

---

#### `setPaymaster(address paymaster)`

Grant PAYMASTER_ROLE to an address.

**Access:** ADMIN_ROLE only

---

#### `upgradeTo(address newImplementation)`

Upgrade contract to new implementation (UUPS).

**Access:** ADMIN_ROLE only

## AppWalletFactory

Factory for deploying EIP-4337 smart contract wallets.

### Read Functions

#### `getWallet(address appContract) → address`

Get deployed wallet address for an app.

**Returns:**
- Wallet address (zero if not deployed)

---

#### `getWalletAddress(address appContract, address operator, bytes32 salt) → address`

Compute the address where a wallet will be deployed.

**Parameters:**
- `appContract`: App contract address
- `operator`: Operator address
- `salt`: CREATE2 salt

**Returns:**
- Predicted wallet address

### Write Functions

#### `createWallet(address appContract, address operator, bytes32 salt) → address`

Deploy a new app wallet using CREATE2.

**Parameters:**
- `appContract`: App contract address
- `operator`: Initial operator address
- `salt`: CREATE2 salt for deterministic address

**Returns:**
- Deployed wallet address

**Requirements:**
- appContract and operator not zero
- Wallet not already created for this app

**Events:**
- `WalletCreated(appContract, wallet, operator)`

**Example:**
```solidity
address wallet = factory.createWallet(
    address(app),
    operatorAddress,
    keccak256(abi.encodePacked("unique-salt"))
);
```

## NovaPaymaster

EIP-4337 Paymaster that sponsors gas for apps.

### Read Functions

#### `gasPriceMarkup() → uint256`

Get gas price markup in basis points (100 = 1%).

### Write Functions

#### `validatePaymasterUserOp(PackedUserOperation userOp, bytes32 userOpHash, uint256 maxCost)`

Validate if paymaster will sponsor this operation.

**Access:** EntryPoint only

**Parameters:**
- `userOp`: User operation to validate
- `userOpHash`: Hash of the operation
- `maxCost`: Maximum cost of the operation

**Returns:**
- `context`: Data to pass to postOp
- `validationData`: 0 if valid, 1 if invalid

**Validation checks:**
1. Valid paymasterAndData format
2. App exists in registry
3. Sender is app's wallet
4. App status is Active
5. Sufficient gas budget

---

#### `postOp(PostOpMode mode, bytes context, uint256 actualGasCost, uint256 actualUserOpFeePerGas)`

Post-operation handler to deduct actual gas cost.

**Access:** EntryPoint only

### Admin Functions

#### `setGasPriceMarkup(uint256 markup)`

Set gas price markup percentage.

**Access:** ADMIN_ROLE only

**Parameters:**
- `markup`: Markup in basis points (max 1000 = 10%)

---

#### `deposit() payable`

Deposit ETH to EntryPoint for this paymaster.

**Access:** ADMIN_ROLE only

---

#### `withdrawFromEntryPoint(address payable withdrawAddress, uint256 amount)`

Withdraw from EntryPoint.

**Access:** ADMIN_ROLE only

## AppWallet

EIP-4337 smart contract wallet with dual control.

### Read Functions

#### `operator() → address`

Get current operator address.

---

#### `appContract() → address`

Get associated app contract address.

---

#### `entryPoint() → address`

Get EntryPoint contract address.

---

#### `novaPlatform() → address`

Get Nova platform contract address.

### Write Functions

#### `validateUserOp(PackedUserOperation userOp, bytes32 userOpHash, uint256 missingAccountFunds) → uint256`

Validate user operation signature.

**Access:** EntryPoint only

**Returns:**
- 0 if valid, 1 if invalid

---

#### `execute(address dest, uint256 value, bytes calldata func)`

Execute a single call.

**Access:** EntryPoint only

**Parameters:**
- `dest`: Destination contract
- `value`: ETH value to send
- `func`: Calldata to execute

---

#### `executeBatch(address[] dests, uint256[] values, bytes[] funcs)`

Execute multiple calls.

**Access:** EntryPoint only

---

#### `updateOperator(address newOperator)`

Update operator address.

**Access:** Nova platform only

**Parameters:**
- `newOperator`: New operator address

**Events:**
- `OperatorUpdated(oldOperator, newOperator)`

## INovaApp Interface

Standard interface for app contracts.

### Required Functions

#### `publisher() → address`

Return publisher (developer) address.

---

#### `novaPlatform() → address`

Return Nova platform contract address.

---

#### `operator() → address`

Return current operator address.

---

#### `setOperator(address operator)`

Set operator address (callable by Nova platform only).

---

#### `requestPCRUpdate(bytes32 pcr0, bytes32 pcr1, bytes32 pcr2)`

Request PCR values update (callable by publisher only).

---

#### `getPCRs() → (bytes32, bytes32, bytes32)`

Return current PCR values.

### Example Implementation

```solidity
contract MyApp is INovaApp {
    address public immutable override publisher;
    address public immutable override novaPlatform;
    address public override operator;
    
    bytes32 public pcr0;
    bytes32 public pcr1;
    bytes32 public pcr2;
    
    constructor(address _publisher, address _novaPlatform) {
        publisher = _publisher;
        novaPlatform = _novaPlatform;
    }
    
    function setOperator(address _operator) external override {
        require(msg.sender == novaPlatform, "Unauthorized");
        operator = _operator;
        emit OperatorUpdated(operator, _operator);
    }
    
    function requestPCRUpdate(bytes32 _pcr0, bytes32 _pcr1, bytes32 _pcr2) 
        external override 
    {
        require(msg.sender == publisher, "Unauthorized");
        pcr0 = _pcr0;
        pcr1 = _pcr1;
        pcr2 = _pcr2;
        INovaRegistry(novaPlatform).updatePCRs(address(this), _pcr0, _pcr1, _pcr2);
        emit PCRsUpdated(_pcr0, _pcr1, _pcr2);
    }
    
    function getPCRs() external view override 
        returns (bytes32, bytes32, bytes32) 
    {
        return (pcr0, pcr1, pcr2);
    }
}
```

## Data Structures

### AppInstance

```solidity
struct AppInstance {
    bytes32 appId;           // Hash of PCRs
    address appContract;     // App contract address
    address operator;        // Current operator
    address walletAddress;   // EIP-4337 wallet
    uint256 version;         // Version number
    InstanceStatus status;   // Current status
    uint256 gasUsed;         // Cumulative gas used
    uint256 gasBudget;       // Remaining budget
    uint256 lastHeartbeat;   // Last heartbeat timestamp
    uint256 registeredAt;    // Registration timestamp
}
```

### AppMetadata

```solidity
struct AppMetadata {
    bytes32 appId;          // keccak256(pcr0, pcr1, pcr2)
    bytes32 pcr0;           // PCR0 value
    bytes32 pcr1;           // PCR1 value
    bytes32 pcr2;           // PCR2 value
    uint256 instanceCount;  // Number of instances
    uint256 latestVersion;  // Latest version number
}
```

### InstanceStatus

```solidity
enum InstanceStatus {
    Registered,  // Waiting for activation
    Active,      // Running
    Inactive,    // Heartbeat expired
    Deleted      // Removed by admin
}
```

## Events Reference

### NovaRegistry Events

```solidity
event AppRegistered(address indexed appContract, bytes32 indexed appId, bytes32 pcr0, bytes32 pcr1, bytes32 pcr2);
event AppActivated(address indexed appContract, address indexed operator, address walletAddress, uint256 version);
event AppInactive(address indexed appContract);
event AppDeleted(address indexed appContract);
event HeartbeatUpdated(address indexed appContract, uint256 timestamp);
event PCRsUpdated(address indexed appContract, bytes32 pcr0, bytes32 pcr1, bytes32 pcr2);
event AppFunded(address indexed appContract, address indexed funder, uint256 amount);
event GasConsumed(address indexed appContract, uint256 amount);
```

### AppWalletFactory Events

```solidity
event WalletCreated(address indexed appContract, address indexed wallet, address indexed operator);
```

### AppWallet Events

```solidity
event OperatorUpdated(address indexed oldOperator, address indexed newOperator);
```

---

**Last Updated**: 2025-11-20  
**Version**: 1.0
