// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {INovaApp} from "../interfaces/INovaApp.sol";
import {INovaRegistry} from "../../nova-contracts/interfaces/INovaRegistry.sol";

/**
 * @title ExampleApp
 * @notice Reference implementation of the INovaApp interface
 * @dev Demonstrates how to implement a Nova-compatible application contract
 *
 * This contract shows:
 * - Role-based access control (publisher, Nova platform, operator)
 * - PCR management and updates
 * - Integration with NovaRegistry
 * - Operator lifecycle management
 */
contract ExampleApp is INovaApp {
    /// @dev Publisher (developer) address
    address public immutable override publisher;

    /// @dev Nova platform registry address
    address public immutable override novaPlatform;

    /// @dev Current operator address (enclave instance)
    address public override operator;

    /// @dev Current registered PCR values
    bytes32 public pcr0;
    bytes32 public pcr1;
    bytes32 public pcr2;

    /// @dev Flag indicating if app is initialized
    bool public initialized;

    /**
     * @dev Error thrown when trying to initialize twice
     */
    error AlreadyInitialized();

    /**
     * @dev Modifier to check caller is publisher
     */
    modifier onlyPublisher() {
        if (msg.sender != publisher) {
            revert Unauthorized();
        }
        _;
    }

    /**
     * @dev Modifier to check caller is Nova platform
     */
    modifier onlyNovaPlatform() {
        if (msg.sender != novaPlatform) {
            revert Unauthorized();
        }
        _;
    }

    /**
     * @dev Modifier to check caller is operator
     */
    modifier onlyOperator() {
        if (msg.sender != operator) {
            revert Unauthorized();
        }
        _;
    }

    /**
     * @dev Constructor
     * @param _publisher Publisher address
     * @param _novaPlatform Nova platform registry address
     */
    constructor(address _publisher, address _novaPlatform) {
        if (_publisher == address(0) || _novaPlatform == address(0)) {
            revert InvalidNovaPlatform();
        }

        publisher = _publisher;
        novaPlatform = _novaPlatform;
    }

    /**
     * @dev Initialize the app with PCR values
     * @param _pcr0 PCR0 value
     * @param _pcr1 PCR1 value
     * @param _pcr2 PCR2 value
     *
     * This should be called before registering with NovaRegistry
     */
    function initialize(
        bytes32 _pcr0,
        bytes32 _pcr1,
        bytes32 _pcr2
    ) external onlyPublisher {
        if (initialized) {
            revert AlreadyInitialized();
        }

        pcr0 = _pcr0;
        pcr1 = _pcr1;
        pcr2 = _pcr2;
        initialized = true;
    }

    /**
     * @inheritdoc INovaApp
     */
    function setOperator(address _operator) external override onlyNovaPlatform {
        if (_operator == address(0)) {
            revert Unauthorized();
        }

        address oldOperator = operator;
        operator = _operator;

        emit OperatorUpdated(oldOperator, _operator);
    }

    /**
     * @inheritdoc INovaApp
     */
    function requestPCRUpdate(
        bytes32 _pcr0,
        bytes32 _pcr1,
        bytes32 _pcr2
    ) external override onlyPublisher {
        // Update local storage
        pcr0 = _pcr0;
        pcr1 = _pcr1;
        pcr2 = _pcr2;

        // Request update in NovaRegistry
        INovaRegistry(novaPlatform).updatePCRs(
            address(this),
            _pcr0,
            _pcr1,
            _pcr2
        );

        emit PCRsUpdated(_pcr0, _pcr1, _pcr2);
    }

    /**
     * @inheritdoc INovaApp
     */
    function getPCRs()
        external
        view
        override
        returns (bytes32, bytes32, bytes32)
    {
        return (pcr0, pcr1, pcr2);
    }

    // ============================================
    // Example Business Logic
    // ============================================

    /// @dev Example: Counter that can be incremented by operator
    uint256 public counter;

    /**
     * @dev Example business function callable by operator
     */
    function incrementCounter() external onlyOperator {
        counter++;
    }

    /**
     * @dev Example business function callable by anyone
     * @param value Value to add to counter
     */
    function addToCounter(uint256 value) external {
        counter += value;
    }

    /**
     * @dev Example: Get app status
     * @return App instance details from NovaRegistry
     */
    function getAppStatus()
        external
        view
        returns (INovaRegistry.AppInstance memory)
    {
        return INovaRegistry(novaPlatform).getAppInstance(address(this));
    }

    /**
     * @dev Example: Fund this app's gas budget
     */
    function fundGasBudget() external payable {
        require(msg.value > 0, "Must send ETH");
        INovaRegistry(novaPlatform).fundApp{value: msg.value}(address(this));
    }
}
