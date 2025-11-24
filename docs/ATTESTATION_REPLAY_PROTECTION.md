# Attestation Replay Protection Implementation Guide

## Problem Statement

**Risk**: Same attestation could be reused multiple times to activate different app instances or impersonate legitimate enclaves.

**Attack Scenario**:
1. Attacker obtains a valid attestation + ZK proof for a legitimate enclave
2. Attacker replays this attestation to activate malicious app contracts
3. Without replay protection, the same attestation passes verification multiple times

## Solution Overview

Implement **multi-layered replay protection** using:
1. **Nonce-based uniqueness** - Each attestation has unique nonce
2. **Attestation hash tracking** - Track used attestations on-chain
3. **Timestamp validation** - Enforce attestation freshness
4. **App-attestation binding** - Bind attestation to specific app contract

## Implementation Strategy

### Level 1: Nonce-Based Protection (Already in VerifierJournal)

The `VerifierJournal` structure already includes a `nonce` field:

```solidity
struct VerifierJournal {
    VerificationResult result;
    uint8 trustedCertsPrefixLen;
    uint64 timestamp;
    bytes32[] certs;
    bytes userData;
    bytes nonce;        // ✅ Already available for replay protection
    bytes publicKey;
    Pcr[] pcrs;
    string moduleId;
}
```

**How it works**:
- Enclave generates random nonce when creating attestation
- Nonce is embedded in attestation document's userData
- ZK proof verifies nonce is in attestation
- On-chain contract tracks used nonces

### Level 2: On-Chain Attestation Tracking

Add tracking mechanism to NovaRegistry:

```solidity
// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

contract NovaRegistry {
    // ... existing code ...

    /// @dev Tracks used attestation hashes to prevent replay
    mapping(bytes32 => bool) private _usedAttestations;
    
    /// @dev Tracks used nonces to prevent replay
    mapping(bytes32 => bool) private _usedNonces;
    
    /// @dev Time window for attestation validity (e.g., 5 minutes)
    uint256 public constant ATTESTATION_VALIDITY_WINDOW = 5 minutes;
    
    /// @dev Error thrown when attestation has already been used
    error AttestationAlreadyUsed();
    
    /// @dev Error thrown when nonce has already been used
    error NonceAlreadyUsed();
    
    /// @dev Error thrown when attestation is too old
    error AttestationExpired();
    
    /// @dev Error thrown when attestation is from the future
    error AttestationFromFuture();
    
    /**
     * @dev Event emitted when attestation is consumed
     */
    event AttestationConsumed(
        address indexed appContract,
        bytes32 indexed attestationHash,
        bytes32 indexed nonceHash,
        uint64 timestamp
    );
    
    /**
     * @dev Validates and marks attestation as used
     * @param journal VerifierJournal from attestation verification
     * @param appContract App contract being activated
     */
    function _validateAndConsumeAttestation(
        VerifierJournal memory journal,
        address appContract
    ) internal {
        // 1. Validate timestamp freshness
        _validateAttestationTimestamp(journal.timestamp);
        
        // 2. Compute attestation hash (includes all critical fields)
        bytes32 attestationHash = _computeAttestationHash(journal);
        
        // 3. Check if attestation already used
        if (_usedAttestations[attestationHash]) {
            revert AttestationAlreadyUsed();
        }
        
        // 4. Check if nonce already used (extra layer)
        bytes32 nonceHash = keccak256(journal.nonce);
        if (_usedNonces[nonceHash]) {
            revert NonceAlreadyUsed();
        }
        
        // 5. Mark as used
        _usedAttestations[attestationHash] = true;
        _usedNonces[nonceHash] = true;
        
        emit AttestationConsumed(
            appContract,
            attestationHash,
            nonceHash,
            journal.timestamp
        );
    }
    
    /**
     * @dev Validates attestation timestamp is within acceptable window
     * @param attestationTimestamp Timestamp from attestation (milliseconds)
     */
    function _validateAttestationTimestamp(uint64 attestationTimestamp) internal view {
        // Convert milliseconds to seconds
        uint256 attestationTime = uint256(attestationTimestamp) / 1000;
        uint256 currentTime = block.timestamp;
        
        // Check attestation is not from future (allow small clock drift)
        if (attestationTime > currentTime + 1 minutes) {
            revert AttestationFromFuture();
        }
        
        // Check attestation is not too old
        if (currentTime > attestationTime + ATTESTATION_VALIDITY_WINDOW) {
            revert AttestationExpired();
        }
    }
    
    /**
     * @dev Computes unique hash for attestation
     * Includes all fields that make attestation unique
     * @param journal VerifierJournal from attestation verification
     * @return Hash of attestation
     */
    function _computeAttestationHash(
        VerifierJournal memory journal
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                journal.timestamp,
                journal.nonce,
                journal.userData,
                journal.publicKey,
                journal.moduleId,
                _encodePCRs(journal.pcrs),
                _encodeCerts(journal.certs)
            )
        );
    }
    
    /**
     * @dev Helper to encode PCR array for hashing
     */
    function _encodePCRs(Pcr[] memory pcrs) internal pure returns (bytes32) {
        bytes memory encoded;
        for (uint256 i = 0; i < pcrs.length; i++) {
            encoded = abi.encodePacked(
                encoded,
                pcrs[i].index,
                pcrs[i].value.first,
                pcrs[i].value.second
            );
        }
        return keccak256(encoded);
    }
    
    /**
     * @dev Helper to encode certificate array for hashing
     */
    function _encodeCerts(bytes32[] memory certs) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(certs));
    }
    
    /**
     * @dev Updated activateApp with replay protection
     */
    function activateApp(
        address appContract,
        bytes calldata output,
        ZkCoProcessorType zkCoprocessor,
        bytes calldata proofBytes
    ) external override onlyRole(PLATFORM_ROLE) {
        if (!_isRegistered[appContract]) {
            revert AppNotFound();
        }

        AppInstance storage instance = _appInstances[appContract];

        if (instance.status == InstanceStatus.Deleted) {
            revert AppNotFound();
        }

        // Verify attestation using ZK proof
        VerifierJournal memory journal = verifier.verify(
            output,
            zkCoprocessor,
            proofBytes
        );
        
        // ✅ NEW: Validate and consume attestation (prevent replay)
        _validateAndConsumeAttestation(journal, appContract);

        // Extract attestation data
        (
            address ethAddress,
            bytes32 tlsPubkeyHash,
            bytes32 pcr0,
            bytes32 pcr1,
            bytes32 pcr2
        ) = journal.extractAttestationData();

        // Validate PCRs match registered values
        AppMetadata storage metadata = _appMetadata[instance.appId];
        journal.validatePCRs(metadata.pcr0, metadata.pcr1, metadata.pcr2);

        // Update instance
        instance.operator = ethAddress;
        instance.walletAddress = ethAddress;
        instance.status = InstanceStatus.Active;
        instance.lastHeartbeat = block.timestamp;

        // Set operator in app contract
        INovaApp(appContract).setOperator(ethAddress);

        emit AppActivated(
            appContract,
            ethAddress,
            ethAddress,
            instance.version
        );
    }
}
```

## Level 3: Enhanced Nonce Generation (Off-Chain)

### Enclave-Side Implementation

The enclave must generate a cryptographically secure nonce that includes:

```rust
// Rust example for enclave-side nonce generation
use rand::RngCore;
use sha2::{Sha256, Digest};

struct AttestationNonce {
    random_bytes: [u8; 32],      // 32 bytes random
    timestamp_ms: u64,            // 8 bytes timestamp
    app_contract: [u8; 20],       // 20 bytes Ethereum address
    purpose: u8,                  // 1 byte purpose flag
}

impl AttestationNonce {
    pub fn generate(app_contract: &str, purpose: NoncePurpose) -> Vec<u8> {
        let mut random_bytes = [0u8; 32];
        rand::thread_rng().fill_bytes(&mut random_bytes);
        
        let timestamp_ms = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis() as u64;
        
        let app_contract_bytes = hex::decode(app_contract.trim_start_matches("0x"))
            .expect("Invalid address");
        
        let mut hasher = Sha256::new();
        hasher.update(&random_bytes);
        hasher.update(&timestamp_ms.to_le_bytes());
        hasher.update(&app_contract_bytes);
        hasher.update(&[purpose as u8]);
        
        hasher.finalize().to_vec()
    }
}

enum NoncePurpose {
    Activation = 0x01,
    OperatorUpdate = 0x02,
    Heartbeat = 0x03,
}
```

### Platform-Side Validation

```typescript
// TypeScript example for platform validation
interface NonceComponents {
  randomBytes: Buffer;
  timestamp: number;
  appContract: string;
  purpose: number;
}

function validateNonceStructure(nonce: Buffer): NonceComponents {
  if (nonce.length !== 32) {
    throw new Error('Invalid nonce length');
  }
  
  // Nonce is a hash, so we can't extract components directly
  // But we can validate it was properly generated in attestation
  return {
    randomBytes: nonce.slice(0, 32),
    timestamp: Date.now(),
    appContract: '0x...',
    purpose: 0x01
  };
}
```

## Level 4: Storage Optimization

To prevent unbounded storage growth, implement cleanup:

```solidity
/// @dev Attestation record with expiry
struct AttestationRecord {
    uint64 timestamp;
    address appContract;
}

/// @dev Track attestations with timestamp for cleanup
mapping(bytes32 => AttestationRecord) private _attestationRecords;

/// @dev Linked list for cleanup (head of old attestations)
bytes32 private _oldestAttestationHash;

/**
 * @dev Cleanup old attestations (admin function)
 * @param maxAge Maximum age of attestations to keep
 */
function cleanupOldAttestations(uint256 maxAge) external onlyRole(ADMIN_ROLE) {
    uint256 cutoffTime = block.timestamp - maxAge;
    // Implementation: Batch delete old attestations
    // Note: In practice, use a more efficient data structure
}
```

## Level 5: Emergency Recovery

Add mechanism to invalidate leaked attestations:

```solidity
/// @dev Mapping to blacklist specific attestation hashes
mapping(bytes32 => bool) private _blacklistedAttestations;

/**
 * @dev Blacklist a specific attestation hash
 * @param attestationHash Hash of attestation to blacklist
 */
function blacklistAttestation(
    bytes32 attestationHash
) external onlyRole(ADMIN_ROLE) {
    _blacklistedAttestations[attestationHash] = true;
    emit AttestationBlacklisted(attestationHash);
}

/**
 * @dev Check in _validateAndConsumeAttestation
 */
function _validateAndConsumeAttestation(
    VerifierJournal memory journal,
    address appContract
) internal {
    bytes32 attestationHash = _computeAttestationHash(journal);
    
    // Check blacklist first
    if (_blacklistedAttestations[attestationHash]) {
        revert AttestationBlacklisted();
    }
    
    // ... rest of validation
}
```

## Testing Strategy

### Unit Tests

```solidity
// Test: Replay prevention
function testCannotReuseAttestation() public {
    // First activation succeeds
    registry.activateApp(app1, output, zkType, proof);
    
    // Second activation with same attestation fails
    vm.expectRevert(NovaRegistry.AttestationAlreadyUsed.selector);
    registry.activateApp(app2, output, zkType, proof);
}

// Test: Nonce replay prevention
function testCannotReuseNonce() public {
    // Create two attestations with same nonce (different data)
    bytes memory output1 = createAttestation(nonce, data1);
    bytes memory output2 = createAttestation(nonce, data2);
    
    registry.activateApp(app1, output1, zkType, proof1);
    
    vm.expectRevert(NovaRegistry.NonceAlreadyUsed.selector);
    registry.activateApp(app2, output2, zkType, proof2);
}

// Test: Timestamp validation
function testRejectsOldAttestation() public {
    // Create attestation with old timestamp
    bytes memory output = createAttestationWithTimestamp(
        block.timestamp - 10 minutes
    );
    
    vm.expectRevert(NovaRegistry.AttestationExpired.selector);
    registry.activateApp(app1, output, zkType, proof);
}

// Test: Future timestamp rejection
function testRejectsFutureAttestation() public {
    bytes memory output = createAttestationWithTimestamp(
        block.timestamp + 2 hours
    );
    
    vm.expectRevert(NovaRegistry.AttestationFromFuture.selector);
    registry.activateApp(app1, output, zkType, proof);
}
```

### Integration Tests

```typescript
describe('Attestation Replay Protection', () => {
  it('should prevent attestation reuse across different apps', async () => {
    // Generate attestation in enclave
    const attestation = await enclave.generateAttestation(app1.address);
    const proof = await zkProver.generateProof(attestation);
    
    // First activation
    await registry.activateApp(app1.address, attestation, proof);
    
    // Try to reuse for different app
    await expect(
      registry.activateApp(app2.address, attestation, proof)
    ).to.be.revertedWith('AttestationAlreadyUsed');
  });
  
  it('should allow new attestation after time window', async () => {
    const attestation1 = await enclave.generateAttestation(app1.address);
    const proof1 = await zkProver.generateProof(attestation1);
    await registry.activateApp(app1.address, attestation1, proof1);
    
    // Wait for validity window to pass
    await time.increase(6 * 60); // 6 minutes
    
    // Generate new attestation (with different nonce)
    const attestation2 = await enclave.generateAttestation(app2.address);
    const proof2 = await zkProver.generateProof(attestation2);
    
    // Should succeed with new attestation
    await registry.activateApp(app2.address, attestation2, proof2);
  });
});
```

## Gas Cost Analysis

| Operation | Estimated Gas | Notes |
|-----------|--------------|-------|
| Attestation hash computation | ~5,000 | One-time per activation |
| SSTORE (new attestation) | ~20,000 | First time storage |
| SSTORE (nonce tracking) | ~20,000 | First time storage |
| SLOAD (replay check) | ~2,100 | Two reads per activation |
| Total overhead | ~47,000 | Additional cost per activation |

**Total activation cost**: ~300k (original) + ~47k (replay protection) = **~347k gas**

## Migration Plan

### Phase 1: Deploy Updated Contract
1. Deploy new NovaRegistry implementation with replay protection
2. Initialize storage mappings
3. Test on testnet

### Phase 2: Upgrade via UUPS
1. Call `upgradeTo()` with new implementation
2. Verify upgrade successful
3. Monitor events for any issues

### Phase 3: Update Off-Chain Components
1. Update enclave code to include nonce in userData
2. Update platform to validate nonce structure
3. Update monitoring to track replay attempts

## Monitoring and Alerts

```typescript
// Alert on replay attempts
registry.on('AttestationAlreadyUsed', (appContract, attestationHash) => {
  logger.error('Replay attack detected', {
    appContract,
    attestationHash,
    severity: 'CRITICAL'
  });
  
  // Trigger incident response
  alertingService.sendCriticalAlert('REPLAY_ATTACK_DETECTED');
});

// Monitor attestation consumption rate
registry.on('AttestationConsumed', (appContract, hash, nonce, timestamp) => {
  metrics.increment('attestations.consumed');
  metrics.gauge('attestation.age', Date.now() - timestamp);
});
```

## Security Considerations

### ✅ Strengths
1. **Multi-layer defense**: Nonce + hash + timestamp
2. **Cryptographically secure**: Uses keccak256 for hashing
3. **Time-bounded**: Attestations expire automatically
4. **Audit trail**: Events for all consumed attestations

### ⚠️ Limitations
1. **Storage growth**: Unbounded if not cleaned up
2. **Clock drift**: Requires synchronized clocks
3. **Gas costs**: Additional ~47k gas per activation

### 🔒 Best Practices
1. Generate nonces with CSPRNG (cryptographically secure random)
2. Include app-specific data in nonce
3. Set appropriate time windows (not too short, not too long)
4. Monitor for replay attempts
5. Implement attestation blacklisting for emergencies
6. Regular cleanup of old attestation records

## Conclusion

This multi-layered approach provides comprehensive replay protection:

1. **Nonce uniqueness** - Each attestation has unique random nonce
2. **Hash tracking** - Full attestation hash prevents any reuse
3. **Time validation** - Limits window for potential replay
4. **App binding** - Nonce can include app-specific data
5. **Emergency controls** - Blacklisting for incident response

The implementation adds modest gas costs (~15% increase) but provides strong security guarantees against replay attacks.

---

**Status**: Ready for implementation  
**Priority**: High (Critical security feature)  
**Estimated effort**: 2-3 days development + 1 week testing
