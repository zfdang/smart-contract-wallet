// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {ZkCoProcessorType, ZkCoProcessorConfig, VerifierJournal, BatchVerifierJournal} from "../types/NitroTypes.sol";

/**
 * @title INitroEnclaveVerifier
 * @notice Interface for AWS Nitro Enclave attestation verification using zero-knowledge proofs
 * @dev This interface defines the contract for verifying AWS Nitro Enclave attestation reports
 * on-chain using zero-knowledge proof systems (RISC Zero or Succinct SP1). The verifier
 * validates the cryptographic integrity of attestation reports while maintaining privacy
 * and reducing gas costs through ZK proofs.
 *
 * Key features:
 * - Single and batch attestation verification
 * - Support for multiple ZK proving systems
 * - Certificate chain management and revocation
 * - Timestamp validation with configurable tolerance
 * - Platform Configuration Register (PCR) verification
 */
interface INitroEnclaveVerifier {
    /**
     * @dev Error thrown when an unsupported or unknown ZK coprocessor type is used
     */
    error Unknown_Zk_Coprocessor();

    /**
     * @dev Returns the maximum allowed time difference for attestation timestamp validation
     * @return Maximum time difference in seconds between attestation time and current block time
     */
    function maxTimeDiff() external view returns (uint64);

    /**
     * @dev Returns the hash of the trusted root certificate
     * @return Hash of the AWS Nitro Enclave root certificate
     */
    function rootCert() external view returns (bytes32);

    /**
     * @dev Revokes a trusted intermediate certificate
     * @param _certHash Hash of the certificate to revoke
     *
     * Requirements:
     * - Only callable by contract owner
     * - Certificate must exist in the trusted set
     */
    function revokeCert(bytes32 _certHash) external;

    /**
     * @dev Checks how many certificates in each report are trusted
     * @param _report_certs Array of certificate chains, each containing certificate hashes
     * @return Array indicating the number of trusted certificates in each chain
     *
     * For each certificate chain:
     * - Validates that the first certificate matches the root certificate
     * - Counts consecutive trusted certificates starting from the root
     * - Returns the count of trusted certificates for each chain
     */
    function checkTrustedIntermediateCerts(bytes32[][] calldata _report_certs)
        external
        view
        returns (uint8[] memory);

    /**
     * @dev Sets the trusted root certificate hash
     * @param _rootCert Hash of the new root certificate
     *
     * Requirements:
     * - Only callable by contract owner
     */
    function setRootCert(bytes32 _rootCert) external;

    /**
     * @dev Configures the zero-knowledge verification parameters for a specific coprocessor
     * @param _zkCoProcessor Type of ZK coprocessor (RiscZero or Succinct)
     * @param _config Configuration parameters including program IDs and verifier address
     *
     * Requirements:
     * - Only callable by contract owner
     * - Must specify valid coprocessor type and configuration
     */
    function setZkConfiguration(ZkCoProcessorType _zkCoProcessor, ZkCoProcessorConfig memory _config) external;

    /**
     * @dev Retrieves the configuration for a specific coprocessor
     * @param _zkCoProcessor Type of ZK coprocessor (RiscZero or Succinct)
     * @return ZkCoProcessorConfig Configuration parameters including program IDs and verifier address
     */
    function getZkConfig(ZkCoProcessorType _zkCoProcessor) external view returns (ZkCoProcessorConfig memory);

    /**
     * @dev Verifies multiple attestation reports in a single batch operation
     * @param output Encoded BatchVerifierJournal containing aggregated verification results
     * @param zkCoprocessor Type of ZK coprocessor used to generate the proof
     * @param proofBytes Zero-knowledge proof data for batch verification
     * @return Array of VerifierJournal results, one for each attestation in the batch
     *
     * This function:
     * 1. Verifies the ZK proof using the specified coprocessor
     * 2. Decodes the batch verification results
     * 3. Validates each attestation's certificate chain and timestamp
     * 4. Caches newly discovered trusted certificates
     * 5. Returns the verification results for all attestations
     */
    function batchVerify(bytes calldata output, ZkCoProcessorType zkCoprocessor, bytes calldata proofBytes)
        external
        returns (VerifierJournal[] memory);

    /**
     * @dev Verifies a single attestation report using zero-knowledge proof
     * @param output Encoded VerifierJournal containing the verification result
     * @param zkCoprocessor Type of ZK coprocessor used to generate the proof
     * @param proofBytes Zero-knowledge proof data for the attestation
     * @return VerifierJournal containing the verification result and extracted data
     *
     * This function:
     * 1. Verifies the ZK proof using the specified coprocessor
     * 2. Decodes the verification result
     * 3. Validates the certificate chain against trusted certificates
     * 4. Checks timestamp validity within the allowed time difference
     * 5. Caches newly discovered trusted certificates
     * 6. Returns the complete verification result
     */
    function verify(bytes calldata output, ZkCoProcessorType zkCoprocessor, bytes calldata proofBytes)
        external
        returns (VerifierJournal memory);
}
