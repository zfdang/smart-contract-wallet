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
 * - Publisher-based access control
 * - PCR initialization workflow
 * - Integration with NovaRegistry
 * - Example business logic
 * - Gas budget management
 */
contract ExampleApp is INovaApp {
    // ============================================
    // State Variables
    // ============================================

    /// @dev Publisher (developer) address - immutable
    address public immutable override publisher;

    /// @dev Nova platform registry address - updatable
    address public override novaPlatform;

    /// @dev PCR values from enclave build
    bytes32 public override pcr0;
    bytes32 public override pcr1;
    bytes32 public override pcr2;

    // ============================================
    // Modifiers
    // ============================================

    /**
     * @dev Modifier to check caller is publisher
     */
    modifier onlyPublisher() {
        if (msg.sender != publisher) {
            revert Unauthorized();
        }
        _;
    }

    // ============================================
    // Constructor
    // ============================================

    /**
     * @dev Constructor
     * @param _publisher Publisher address (your address)
     * @param _novaPlatform Nova platform registry address
     */
    constructor(address _publisher, address _novaPlatform) {
        if (_publisher == address(0) || _novaPlatform == address(0)) {
            revert InvalidPlatform();
        }

        publisher = _publisher;
        novaPlatform = _novaPlatform;
    }

    // ============================================
    // INovaApp Implementation
    // ============================================

    /**
     * @inheritdoc INovaApp
     */
    function initialize(
        bytes32 _pcr0,
        bytes32 _pcr1,
        bytes32 _pcr2
    ) external override onlyPublisher {
        // Check not already initialized
        if (pcr0 != bytes32(0)) {
            revert AlreadyInitialized();
        }

        // Validate PCRs
        if (_pcr0 == bytes32(0) || _pcr1 == bytes32(0) || _pcr2 == bytes32(0)) {
            revert InvalidPCRs();
        }

        // Store PCRs
        pcr0 = _pcr0;
        pcr1 = _pcr1;
        pcr2 = _pcr2;

        emit PCRsInitialized(_pcr0, _pcr1, _pcr2);
    }

    /**
     * @inheritdoc INovaApp
     */
    function updatePlatform(address _novaPlatform) external override onlyPublisher {
        if (_novaPlatform == address(0)) {
            revert InvalidPlatform();
        }

        address oldPlatform = novaPlatform;
        novaPlatform = _novaPlatform;

        emit PlatformUpdated(oldPlatform, _novaPlatform);
    }

    // ============================================
    // Example Business Logic
    // ============================================

    /// @dev Example state: Simple counter
    uint256 public counter;

    /// @dev Example state: User balances
    mapping(address => uint256) public userBalances;

    /**
     * @dev Example function: Increment counter
     * @notice Anyone can increment the counter
     */
    function incrementCounter() external {
        counter++;
    }

    /**
     * @dev Example function: Add value to counter
     * @param value Value to add
     */
    function addToCounter(uint256 value) external {
        counter += value;
    }

    /**
     * @dev Example function: Deposit ETH
     * @notice Users can deposit ETH to their balance
     */
    function deposit() external payable {
        require(msg.value > 0, "Must send ETH");
        userBalances[msg.sender] += msg.value;
    }

    /**
     * @dev Example function: Withdraw ETH
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 amount) external {
        require(userBalances[msg.sender] >= amount, "Insufficient balance");
        userBalances[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
    }

    // ============================================
    // Registry Integration Helpers
    // ============================================

    /**
     * @dev Get this app's status from NovaRegistry
     * @return App instance details
     */
    function getAppStatus() external view returns (INovaRegistry.AppInstance memory) {
        return INovaRegistry(novaPlatform).getAppInstance(address(this));
    }

    /**
     * @dev Fund this app's gas budget
     * @notice Anyone can fund the app's gas budget
     */
    function fundGasBudget() external payable {
        require(msg.value > 0, "Must send ETH");
        INovaRegistry(novaPlatform).fundApp{value: msg.value}(address(this));
    }

    /**
     * @dev Get current gas budget
     * @return Current gas budget in wei
     */
    function getGasBudget() external view returns (uint256) {
        INovaRegistry.AppInstance memory instance = INovaRegistry(novaPlatform).getAppInstance(address(this));
        return instance.gasBudget;
    }

    /**
     * @dev Get version history
     * @return Array of appIds representing version history
     */
    function getVersionHistory() external view returns (bytes32[] memory) {
        return INovaRegistry(novaPlatform).getVersionHistory(address(this));
    }

    /**
     * @dev Check if app is active
     * @return true if app status is Active
     */
    function isActive() external view returns (bool) {
        INovaRegistry.AppInstance memory instance = INovaRegistry(novaPlatform).getAppInstance(address(this));
        return instance.status == INovaRegistry.InstanceStatus.Active;
    }
}
