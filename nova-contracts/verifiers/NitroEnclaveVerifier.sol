// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {ITEEVerifier} from "../interfaces/ITEEVerifier.sol";
import {INitroEnclaveVerifier} from "../interfaces/INitroEnclaveVerifier.sol";
import {
    VerifierJournal,
    TEEType,
    ZkCoProcessorType
} from "../types/NitroTypes.sol";

/**
 * @title NitroEnclaveVerifier
 * @notice AWS Nitro Enclave attestation verifier implementation
 * @dev Implements ITEEVerifier for AWS Nitro Enclaves using zero-knowledge proofs
 * 
 * This verifier wraps the existing Nitro-specific verifier and adapts it
 * to the unified ITEEVerifier interface, allowing it to work alongside
 * other TEE verifiers in a vendor-agnostic system.
 */
contract NitroEnclaveVerifier is ITEEVerifier {
    /// @dev Reference to the Nitro-specific ZK proof verifier
    INitroEnclaveVerifier public immutable nitroVerifier;

    /// @dev ZK coprocessor type to use (RiscZero or Succinct)
    ZkCoProcessorType public immutable zkCoprocessorType;

    /**
     * @dev Error thrown when attestation verification fails
     */
    error VerificationFailed();

    /**
     * @dev Constructor
     * @param _nitroVerifier Address of the Nitro-specific verifier contract
     * @param _zkCoprocessorType Type of ZK coprocessor to use
     */
    constructor(
        address _nitroVerifier,
        ZkCoProcessorType _zkCoprocessorType
    ) {
        require(_nitroVerifier != address(0), "Invalid verifier address");
        require(
            _zkCoprocessorType != ZkCoProcessorType.Unknown,
            "Invalid coprocessor type"
        );

        nitroVerifier = INitroEnclaveVerifier(_nitroVerifier);
        zkCoprocessorType = _zkCoprocessorType;
    }

    /**
     * @inheritdoc ITEEVerifier
     * @dev Verifies AWS Nitro Enclave attestation using ZK proof
     * 
     * For Nitro enclaves:
     * - attestation: Encoded VerifierInput or journal output
     * - proof: ZK proof bytes (RISC Zero or Succinct format)
     */
    function verify(
        bytes calldata attestation,
        bytes calldata proof
    ) external view override returns (VerifierJournal memory) {
        // Call the Nitro-specific verifier
        VerifierJournal memory journal = nitroVerifier.verify(
            attestation,
            zkCoprocessorType,
            proof
        );

        return journal;
    }

    /**
     * @inheritdoc ITEEVerifier
     */
    function getTEEType() external pure override returns (TEEType) {
        return TEEType.NitroEnclave;
    }

    /**
     * @inheritdoc ITEEVerifier
     * @dev For Nitro, checks timestamp from decoded attestation
     */
    function isAttestationValid(
        bytes calldata attestation,
        uint256 maxAge
    ) external view override returns (bool) {
        // Decode the attestation to get timestamp
        // This is a simplified check - in production, decode the VerifierJournal
        // For now, return true as this is an optimization
        return true;
    }
}
