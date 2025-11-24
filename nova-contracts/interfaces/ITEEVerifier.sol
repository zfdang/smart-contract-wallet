// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {VerifierJournal, TEEType} from "../types/NitroTypes.sol";

/**
 * @title ITEEVerifier
 * @notice Unified interface for Trusted Execution Environment (TEE) attestation verifiers
 * @dev All TEE verifiers (AWS Nitro, Intel SGX, AMD SEV) must implement this interface
 * 
 * This abstraction allows the Nova platform to support multiple TEE vendors without
 * being locked into a single provider. Each verifier implementation handles the
 * specific attestation format and cryptographic verification for its TEE type.
 */
interface ITEEVerifier {
    /**
     * @dev Verify a TEE attestation and return the verified journal
     * @param attestation Raw attestation data (format varies by TEE type)
     * @param proof Zero-knowledge proof or other cryptographic proof of attestation validity
     * @return journal Verified attestation data in standardized format
     * 
     * Requirements:
     * - Must verify cryptographic signatures
     * - Must validate certificate chains
     * - Must check timestamp validity
     * - Must extract all relevant data into VerifierJournal
     * 
     * Reverts if:
     * - Attestation signature is invalid
     * - Certificate chain cannot be verified
     * - Timestamp is outside acceptable range
     * - Attestation format is malformed
     */
    function verify(
        bytes calldata attestation,
        bytes calldata proof
    ) external view returns (VerifierJournal memory journal);

    /**
     * @dev Get the TEE type that this verifier supports
     * @return TEE type (NitroEnclave, IntelSGX, or AMDSEV)
     */
    function getTEEType() external pure returns (TEEType);

    /**
     * @dev Check if an attestation is still valid based on age
     * @param attestation Raw attestation data
     * @param maxAge Maximum acceptable age in seconds
     * @return bool True if attestation is valid and not expired
     * 
     * This is a lightweight check that can be used for quick validation
     * without performing full cryptographic verification.
     */
    function isAttestationValid(
        bytes calldata attestation,
        uint256 maxAge
    ) external view returns (bool);
}
