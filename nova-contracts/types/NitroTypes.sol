// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

/**
 * @title Nitro Enclave Attestation Types
 * @notice Type definitions for TEE attestation verification (AWS Nitro, Intel SGX, AMD SEV)
 * @dev These types are used for zero-knowledge proof verification of attestation reports
 */

/**
 * @dev Enumeration of supported Trusted Execution Environment (TEE) types
 * Used to specify which TEE vendor's attestation is being verified
 */
enum TEEType {
    // AWS Nitro Enclaves
    NitroEnclave,
    // Intel Software Guard Extensions (SGX)
    IntelSGX,
    // AMD Secure Encrypted Virtualization (SEV-SNP)
    AMDSEV
}

/**
 * @dev Enumeration of supported zero-knowledge proof coprocessor types
 * Used to specify which proving system to use for attestation verification
 */
enum ZkCoProcessorType {
    Unknown,
    // RISC Zero zkVM proving system
    RiscZero,
    // Succinct SP1 proving system
    Succinct
}

/**
 * @dev Configuration parameters for a specific zero-knowledge coprocessor
 * Contains all necessary identifiers and addresses for ZK proof verification
 */
struct ZkCoProcessorConfig {
    // Program ID for single attestation verification
    bytes32 verifierId;
    // Verifier Proof ID used for batch proof verification in aggregator
    bytes32 verifierProofId;
    // Program ID for batch/aggregated verification
    bytes32 aggregatorId;
    // Address of the ZK verifier contract (RiscZero or SP1)
    address zkVerifier;
}

/**
 * @dev Input structure for attestation report verification
 * Contains the raw attestation data and trusted certificate chain length
 */
struct VerifierInput {
    // Number of trusted certificates in the chain
    uint8 trustedCertsPrefixLen;
    // Raw AWS Nitro Enclave attestation report (COSE_Sign1 format)
    bytes attestationReport;
}

/**
 * @dev Output structure containing verified attestation data and metadata
 * This represents the journal/output from zero-knowledge proof verification
 */
struct VerifierJournal {
    // Overall verification result status
    VerificationResult result;
    // Number of certificates that were trusted during verification
    uint8 trustedCertsPrefixLen;
    // Attestation timestamp (Unix timestamp in milliseconds)
    uint64 timestamp;
    // Array of certificate hashes in the chain (root to leaf)
    bytes32[] certs;
    // User-defined data embedded in the attestation
    bytes userData;
    // Cryptographic nonce used for replay protection
    bytes nonce;
    // Public key extracted from the attestation
    bytes publicKey;
    // Platform Configuration Registers (integrity measurements)
    Pcr[] pcrs;
    // AWS Nitro Enclave module identifier
    string moduleId;
}

/**
 * @dev Input structure for batch verification operations
 * Used when aggregating multiple attestation verifications
 */
struct BatchVerifierInput {
    // Verification key for the batch verifier program
    bytes32 verifierVk;
    // Array of individual verification results to aggregate
    VerifierJournal[] outputs;
}

/**
 * @dev Output structure for batch verification operations
 * Contains the aggregated results of multiple attestation verifications
 */
struct BatchVerifierJournal {
    // Verification key that was used for batch verification
    bytes32 verifierVk;
    // Array of verified attestation results
    VerifierJournal[] outputs;
}

/**
 * @dev 48-byte data structure for storing PCR values
 * Split into two parts due to Solidity's 32-byte word limitation
 */
struct Bytes48 {
    bytes32 first;
    bytes16 second;
}

/**
 * @dev Platform Configuration Register (PCR) entry
 * PCRs contain cryptographic measurements of the enclave's runtime state
 */
struct Pcr {
    // PCR index number (0-23 for AWS Nitro Enclaves)
    uint64 index;
    // 48-byte PCR measurement value (SHA-384 hash)
    Bytes48 value;
}

/**
 * @dev Enumeration of possible attestation verification results
 * Indicates the outcome of the verification process
 */
enum VerificationResult {
    // Attestation successfully verified
    Success,
    // Root certificate is not in the trusted set
    RootCertNotTrusted,
    // One or more intermediate certificates are not trusted
    IntermediateCertsNotTrusted,
    // Attestation timestamp is outside acceptable range
    InvalidTimestamp
}
