// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

/**
 * @title INovaApp
 * @notice Standard interface that all Nova platform applications must implement
 * @dev This interface ensures consistent interaction between the Nova platform and application contracts.
 * App contracts implementing this interface can be registered and managed by the NovaRegistry contract.
 */
interface INovaApp {
    /**
     * @dev Emitted when the operator address is updated
     * @param oldOperator Previous operator address
     * @param newOperator New operator address
     */
    event OperatorUpdated(address indexed oldOperator, address indexed newOperator);

    /**
     * @dev Emitted when PCRs are updated
     * @param pcr0 New PCR0 value
     * @param pcr1 New PCR1 value
     * @param pcr2 New PCR2 value
     */
    event PCRsUpdated(bytes32 pcr0, bytes32 pcr1, bytes32 pcr2);

    /**
     * @dev Error thrown when caller is not authorized
     */
    error Unauthorized();

    /**
     * @dev Error thrown when the Nova platform address is invalid
     */
    error InvalidNovaPlatform();

    /**
     * @dev Returns the address of the application publisher (developer)
     * @return Address of the publisher who deployed this app contract
     */
    function publisher() external view returns (address);

    /**
     * @dev Returns the address of the Nova platform contract
     * @return Address of the NovaRegistry contract
     */
    function novaPlatform() external view returns (address);

    /**
     * @dev Returns the current operator address
     * @return Address of the operator (enclave instance wallet)
     */
    function operator() external view returns (address);

    /**
     * @dev Sets a new operator address
     * @param _operator New operator address to be set
     *
     * Requirements:
     * - Only callable by the Nova platform contract
     * - The new operator address must not be zero address
     *
     * Emits an {OperatorUpdated} event
     */
    function setOperator(address _operator) external;

    /**
     * @dev Requests an update to the registered PCRs
     * @param pcr0 New PCR0 value
     * @param pcr1 New PCR1 value
     * @param pcr2 New PCR2 value
     *
     * Requirements:
     * - Only callable by the publisher
     * - Triggers a call to NovaRegistry to update PCRs
     *
     * Emits a {PCRsUpdated} event
     */
    function requestPCRUpdate(bytes32 pcr0, bytes32 pcr1, bytes32 pcr2) external;

    /**
     * @dev Returns the currently registered PCR values
     * @return pcr0 PCR0 value
     * @return pcr1 PCR1 value
     * @return pcr2 PCR2 value
     */
    function getPCRs() external view returns (bytes32 pcr0, bytes32 pcr1, bytes32 pcr2);
}
