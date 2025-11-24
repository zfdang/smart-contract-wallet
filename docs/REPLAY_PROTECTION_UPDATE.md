# NovaRegistry Replay Protection Update

## Overview

This update adds comprehensive attestation replay protection to the NovaRegistry contract, preventing malicious actors from reusing valid attestations to activate unauthorized app instances.

## Changes Summary

### 1. NovaRegistry.sol

**New Storage Variables:**
```solidity
/// @dev Tracks used attestation hashes to prevent replay attacks
mapping(bytes32 => bool) private _usedAttestations;

/// @dev Tracks used nonces to prevent replay attacks (extra layer)
mapping(bytes32 => bool) private _usedNonces;

/// @dev Time window for attestation validity (5 minutes)
uint256 public constant ATTESTATION_VALIDITY_WINDOW = 5 minutes;
```

**New Internal Functions:**

1. **`_validateAndConsumeAttestation()`**
   - Validates attestation timestamp freshness
   - Computes unique attestation hash
   - Checks if attestation or nonce already used
   - Marks both as consumed
   - Emits `AttestationConsumed` event

2. **`_validateAttestationTimestamp()`**
   - Checks attestation is not from the future (allows 1 min clock drift)
   - Checks attestation is not too old (5 minute validity window)

3. **`_computeAttestationHash()`**
   - Computes unique hash including:
     - timestamp
     - nonce
     - userData
     - publicKey
     - moduleId
     - PCRs
     - Certificate chain

4. **`_encodePCRs()` and `_encodeCerts()`**
   - Helper functions for attestation hash computation

**Modified Functions:**

- **`activateApp()`**: Now calls `_validateAndConsumeAttestation()` immediately after ZK proof verification

### 2. INovaRegistry.sol

**New Event:**
```solidity
event AttestationConsumed(
    address indexed appContract, 
    bytes32 indexed attestationHash, 
    bytes32 indexed nonceHash, 
    uint64 timestamp
);
```

**New Errors:**
```solidity
error AttestationAlreadyUsed();
error NonceAlreadyUsed();
error AttestationExpired();
error AttestationFromFuture();
```

## Security Improvements

### Multi-Layer Defense

| Layer | Mechanism | Protection |
|-------|-----------|------------|
| 1 | Nonce uniqueness | Each attestation has unique random nonce |
| 2 | Hash tracking | Full attestation hash prevents any reuse |
| 3 | Time validation | Limits window for potential replay |
| 4 | Dual tracking | Both hash and nonce checked separately |

### Attack Scenarios Prevented

✅ **Scenario 1: Same Attestation Replay**
- Attacker reuses valid attestation for different app
- **Blocked by**: `_usedAttestations` mapping

✅ **Scenario 2: Nonce Collision**
- Attacker tries different attestation with same nonce
- **Blocked by**: `_usedNonces` mapping

✅ **Scenario 3: Stale Attestation**
- Attacker uses old leaked attestation
- **Blocked by**: Time window validation

✅ **Scenario 4: Future Attestation**
- Attacker pre-generates attestation with future timestamp
- **Blocked by**: Future timestamp rejection

## Gas Cost Impact

| Operation | Original Gas | New Gas | Increase |
|-----------|-------------|---------|----------|
| activateApp() | ~300,000 | ~347,000 | +47,000 (~15%) |

**Breakdown of Additional Costs:**
- Attestation hash computation: ~5,000 gas
- SSTORE (attestation): ~20,000 gas
- SSTORE (nonce): ~20,000 gas
- SLOAD checks: ~2,000 gas

## Testing

### Test Coverage

New test file: `test/NovaRegistry.replay.t.sol`

**Test Cases:**

1. ✅ Normal activation succeeds
2. ✅ Cannot reuse same attestation for different app
3. ✅ Cannot reuse same nonce with different data
4. ✅ Reject attestation that is too old (>5 minutes)
5. ✅ Reject attestation from the future (>1 minute)
6. ✅ Allow attestation within validity window
7. ✅ Allow small clock drift (±1 minute)
8. ✅ Different attestations with unique nonces work fine
9. ✅ AttestationConsumed event is emitted

### Running Tests

```bash
# Run all replay protection tests
forge test --match-contract NovaRegistryReplayTest -vvv

# Run specific test
forge test --match-test testCannotReuseSameAttestation -vvv

# Run with gas reporting
forge test --match-contract NovaRegistryReplayTest --gas-report
```

## Deployment & Migration

### For New Deployments

Simply deploy the updated NovaRegistry contract - replay protection is built-in.

### For Existing Deployments (UUPS Upgrade)

```solidity
// 1. Deploy new implementation
NovaRegistry newImpl = new NovaRegistry();

// 2. Upgrade via UUPS proxy (as admin)
NovaRegistry(proxyAddress).upgradeTo(address(newImpl));

// 3. Verify upgrade
require(
    NovaRegistry(proxyAddress).ATTESTATION_VALIDITY_WINDOW() == 5 minutes,
    "Upgrade failed"
);
```

**Storage Layout Compatibility:**

✅ **Safe** - New mappings added at the end of storage
- `_usedAttestations` (slot N+1)
- `_usedNonces` (slot N+2)
- No existing storage modified

**Upgrade Checklist:**

- [ ] Deploy new implementation contract
- [ ] Test on testnet first
- [ ] Verify storage layout compatibility
- [ ] Execute upgrade transaction
- [ ] Monitor AttestationConsumed events
- [ ] Test activation with new attestations

## Configuration

### Attestation Validity Window

Default: **5 minutes**

Can be modified by changing the constant:
```solidity
uint256 public constant ATTESTATION_VALIDITY_WINDOW = 5 minutes;
```

**Considerations:**
- **Too short**: May reject valid attestations due to network delays
- **Too long**: Larger window for potential replay attacks
- **Recommended**: 5-10 minutes for production

### Clock Drift Tolerance

Default: **1 minute**

Allows for small clock differences between enclave and blockchain:
```solidity
if (attestationTime > currentTime + 1 minutes) {
    revert AttestationFromFuture();
}
```

## Monitoring

### Events to Monitor

```typescript
// Alert on replay attempts
registry.on('AttestationAlreadyUsed', () => {
  logger.error('CRITICAL: Replay attack detected!');
  alertingService.sendAlert('REPLAY_ATTACK');
});

// Track normal consumption
registry.on('AttestationConsumed', (app, hash, nonce, timestamp) => {
  metrics.increment('attestations.consumed');
  metrics.gauge('attestation.age', Date.now() - timestamp);
});
```

### Recommended Alerts

1. **Replay Attempt Detection**
   - Trigger: `AttestationAlreadyUsed` or `NonceAlreadyUsed` error
   - Severity: CRITICAL
   - Action: Investigate immediately

2. **Expired Attestations**
   - Trigger: Multiple `AttestationExpired` errors
   - Severity: WARNING
   - Action: Check platform timing/delays

3. **Future Attestations**
   - Trigger: `AttestationFromFuture` error
   - Severity: HIGH
   - Action: Check for clock sync issues or attack

## Off-Chain Requirements

### Enclave Changes

The enclave must generate proper nonces in attestations:

```rust
// Generate cryptographically secure nonce
let mut nonce = [0u8; 32];
rand::thread_rng().fill_bytes(&mut nonce);

// Include in attestation userData
let user_data = encode_user_data(eth_address, tls_pubkey, nonce);
```

### Platform Changes

The platform should:

1. **Validate Nonce Structure** (optional)
   ```typescript
   if (nonce.length !== 32) {
     throw new Error('Invalid nonce length');
   }
   ```

2. **Monitor for Replay Attempts**
   ```typescript
   try {
     await registry.activateApp(app, output, zkType, proof);
   } catch (error) {
     if (error.message.includes('AttestationAlreadyUsed')) {
       logger.error('Replay attack detected', { app, error });
       // Trigger incident response
     }
   }
   ```

3. **Track Attestation Age**
   ```typescript
   const attestationAge = Date.now() - journal.timestamp;
   if (attestationAge > 4 * 60 * 1000) { // 4 minutes
     logger.warn('Attestation close to expiry', { age: attestationAge });
   }
   ```

## Future Enhancements

### Potential Improvements

1. **Storage Cleanup**
   ```solidity
   // Admin function to clean old attestations
   function cleanupOldAttestations(uint256 maxAge) external onlyRole(ADMIN_ROLE) {
       // Remove attestations older than maxAge
   }
   ```

2. **Attestation Blacklist**
   ```solidity
   // Emergency blacklist for compromised attestations
   mapping(bytes32 => bool) private _blacklistedAttestations;
   ```

3. **Dynamic Validity Window**
   ```solidity
   // Allow admin to adjust validity window
   uint256 public attestationValidityWindow = 5 minutes;
   
   function setValidityWindow(uint256 newWindow) external onlyRole(ADMIN_ROLE) {
       attestationValidityWindow = newWindow;
   }
   ```

4. **Batch Attestation Cleanup**
   - Use Merkle tree for efficient storage
   - Periodic cleanup of old attestations
   - Optimize gas costs for long-term operation

## Security Audit Status

- [x] Self-review completed
- [x] Unit tests written and passing
- [ ] Integration tests needed
- [ ] External security audit recommended
- [ ] Formal verification (optional)

## References

- **Design Document**: `docs/DESIGN.md` (Section: Potential Security Issues)
- **Implementation Guide**: `docs/ATTESTATION_REPLAY_PROTECTION.md`
- **Test Suite**: `test/NovaRegistry.replay.t.sol`

## Support

For questions or issues:
- Review implementation guide: `docs/ATTESTATION_REPLAY_PROTECTION.md`
- Check test examples: `test/NovaRegistry.replay.t.sol`
- Open issue in repository

---

**Version**: 1.0.0  
**Date**: 2025-11-24  
**Status**: ✅ Implementation Complete, Testing In Progress
