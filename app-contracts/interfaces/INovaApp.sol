// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

/**
 * @title INovaApp
 * @notice Standard interface that all Nova platform applications must implement
 * @dev This interface ensures consistent interaction between the Nova platform and application contracts.
 * 
 * App contracts implementing this interface can be registered and managed by the NovaRegistry contract.
 * The interface provides:
 * - Publisher identification and control
 * - Nova platform registry reference
 * - PCR (Platform Configuration Register) management
 * - Initialization lifecycle
 */
interface INovaApp {
    // ============================================
    // Events
    // ============================================

    /**
     * @dev Emitted when PCRs are initialized
     * @param pcr0 PCR0 value
     * @param pcr1 PCR1 value
     * @param pcr2 PCR2 value
     */
    event PCRsInitialized(bytes32 pcr0, bytes32 pcr1, bytes32 pcr2);

    /**
     * @dev Emitted when the Nova platform address is updated
     * @param oldPlatform Previous platform address
     * @param newPlatform New platform address
     */
    event PlatformUpdated(address indexed oldPlatform, address indexed newPlatform);

    // ============================================
    // Errors
    // ============================================

    /**
     * @dev Error thrown when caller is not authorized
     */
    error Unauthorized();

    /**
     * @dev Error thrown when the Nova platform address is invalid
     */
    error InvalidPlatform();

    /**
     * @dev Error thrown when PCR values are invalid
     */
    error InvalidPCRs();

    /**
     * @dev Error thrown when app is already initialized
     */
    error AlreadyInitialized();

    // ============================================
    // View Functions
    // ============================================

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
     * @dev Returns PCR0 value
     * @return PCR0 (Platform Configuration Register 0)
     */
    function pcr0() external view returns (bytes32);

    /**
     * @dev Returns PCR1 value
     * @return PCR1 (Platform Configuration Register 1)
     */
    function pcr1() external view returns (bytes32);

    /**
     * @dev Returns PCR2 value
     * @return PCR2 (Platform Configuration Register 2)
     */
    function pcr2() external view returns (bytes32);

    // ============================================
    // State-Changing Functions
    // ============================================

    /**
     * @dev Initialize the app with PCR values
     * @param _pcr0 PCR0 value from enclave build
     * @param _pcr1 PCR1 value from enclave build
     * @param _pcr2 PCR2 value from enclave build
     *
     * Requirements:
     * - Only callable by the publisher
     * - Can only be called once
     * - PCR values must not be zero
     *
     * Emits a {PCRsInitialized} event
     * 
     * @notice This must be called before registering with NovaRegistry
     */
    function initialize(
        bytes32 _pcr0,
        bytes32 _pcr1,
        bytes32 _pcr2
    ) external;

    /**
     * @dev Update the Nova platform registry address
     * @param _novaPlatform New platform address
     *
     * Requirements:
     * - Only callable by the publisher
     * - New platform address must not be zero
     *
     * Emits a {PlatformUpdated} event
     * 
     * @notice Use this to upgrade to a new NovaRegistry deployment
     */
    function updatePlatform(address _novaPlatform) external;
}
