// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {VerifierJournal, Pcr, VerificationResult} from "../types/NitroTypes.sol";

/**
 * @title AttestationLib
 * @notice Library for processing AWS Nitro Enclave attestation data
 * @dev Provides helper functions for extracting and validating attestation information
 */
library AttestationLib {
    /**
     * @dev Error thrown when attestation verification failed
     */
    error AttestationVerificationFailed();

    /**
     * @dev Error thrown when required PCRs are missing
     */
    error MissingRequiredPCRs();

    /**
     * @dev Error thrown when PCR values don't match expected values
     */
    error PCRMismatch();

    /**
     * @dev Error thrown when userData format is invalid
     */
    error InvalidUserDataFormat();

    /**
     * @dev Validates that the attestation verification was successful
     * @param journal VerifierJournal from attestation verification
     * @return true if verification succeeded
     */
    function isVerificationSuccessful(VerifierJournal memory journal) internal pure returns (bool) {
        return journal.result == VerificationResult.Success;
    }

    /**
     * @dev Extracts ETH address and TLS public key from userData
     * @param userData Encoded user data from attestation
     * @return ethAddress Extracted Ethereum address
     * @return tlsPubkey Extracted TLS public key
     *
     * Assumes userData format: abi.encode(address ethAddress, bytes tlsPubkey)
     */
    function extractUserData(bytes memory userData) internal pure returns (address ethAddress, bytes memory tlsPubkey) {
        if (userData.length < 32) {
            revert InvalidUserDataFormat();
        }

        (ethAddress, tlsPubkey) = abi.decode(userData, (address, bytes));

        if (ethAddress == address(0)) {
            revert InvalidUserDataFormat();
        }
    }

    /**
     * @dev Extracts PCR values from the attestation
     * @param journal VerifierJournal from attestation verification
     * @return pcr0 PCR0 value (32 bytes)
     * @return pcr1 PCR1 value (32 bytes)
     * @return pcr2 PCR2 value (32 bytes)
     *
     * Note: PCR values are 48 bytes (SHA-384), but we only use the first 32 bytes for efficiency
     */
    function extractPCRs(VerifierJournal memory journal)
        internal
        pure
        returns (bytes32 pcr0, bytes32 pcr1, bytes32 pcr2)
    {
        bool foundPcr0 = false;
        bool foundPcr1 = false;
        bool foundPcr2 = false;

        for (uint256 i = 0; i < journal.pcrs.length; i++) {
            Pcr memory pcr = journal.pcrs[i];

            if (pcr.index == 0) {
                pcr0 = pcr.value.first;
                foundPcr0 = true;
            } else if (pcr.index == 1) {
                pcr1 = pcr.value.first;
                foundPcr1 = true;
            } else if (pcr.index == 2) {
                pcr2 = pcr.value.first;
                foundPcr2 = true;
            }

            // Early exit if all required PCRs found
            if (foundPcr0 && foundPcr1 && foundPcr2) {
                break;
            }
        }

        if (!foundPcr0 || !foundPcr1 || !foundPcr2) {
            revert MissingRequiredPCRs();
        }
    }

    /**
     * @dev Validates that PCRs from attestation match expected values
     * @param journal VerifierJournal from attestation verification
     * @param expectedPcr0 Expected PCR0 value
     * @param expectedPcr1 Expected PCR1 value
     * @param expectedPcr2 Expected PCR2 value
     * @return true if PCRs match
     */
    function validatePCRs(
        VerifierJournal memory journal,
        bytes32 expectedPcr0,
        bytes32 expectedPcr1,
        bytes32 expectedPcr2
    ) internal pure returns (bool) {
        (bytes32 pcr0, bytes32 pcr1, bytes32 pcr2) = extractPCRs(journal);

        if (pcr0 != expectedPcr0 || pcr1 != expectedPcr1 || pcr2 != expectedPcr2) {
            revert PCRMismatch();
        }

        return true;
    }

    /**
     * @dev Computes app ID from PCR values
     * @param pcr0 PCR0 value
     * @param pcr1 PCR1 value
     * @param pcr2 PCR2 value
     * @return appId Computed app identifier
     */
    function computeAppId(bytes32 pcr0, bytes32 pcr1, bytes32 pcr2) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(pcr0, pcr1, pcr2));
    }

    /**
     * @dev Hashes TLS public key for storage
     * @param tlsPubkey TLS public key bytes
     * @return Hash of the TLS public key
     */
    function hashTLSPubkey(bytes memory tlsPubkey) internal pure returns (bytes32) {
        return keccak256(tlsPubkey);
    }

    /**
     * @dev Extracts all relevant data from attestation journal
     * @param journal VerifierJournal from attestation verification
     * @return ethAddress Extracted Ethereum address
     * @return tlsPubkeyHash Hash of TLS public key
     * @return pcr0 PCR0 value
     * @return pcr1 PCR1 value
     * @return pcr2 PCR2 value
     */
    function extractAttestationData(VerifierJournal memory journal)
        internal
        pure
        returns (address ethAddress, bytes32 tlsPubkeyHash, bytes32 pcr0, bytes32 pcr1, bytes32 pcr2)
    {
        // Validate verification succeeded
        if (!isVerificationSuccessful(journal)) {
            revert AttestationVerificationFailed();
        }

        // Extract user data
        bytes memory tlsPubkey;
        (ethAddress, tlsPubkey) = extractUserData(journal.userData);
        tlsPubkeyHash = hashTLSPubkey(tlsPubkey);

        // Extract PCRs
        (pcr0, pcr1, pcr2) = extractPCRs(journal);
    }
}
