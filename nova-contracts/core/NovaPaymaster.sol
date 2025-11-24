// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {IPaymaster, PackedUserOperation, PostOpMode} from "../interfaces/IEntryPoint.sol";
import {INovaRegistry} from "../interfaces/INovaRegistry.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title NovaPaymaster
 * @notice EIP-4337 Paymaster that sponsors gas for registered Nova apps
 * @dev Validates operations against app gas budgets in NovaRegistry
 *
 * Features:
 * - Sponsors gas for registered app wallets
 * - Validates against per-app gas budgets
 * - Tracks actual gas consumption
 * - Integrates with NovaRegistry for budget management
 */
contract NovaPaymaster is IPaymaster, AccessControl {
    /// @dev Role for admin operations
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @dev EntryPoint contract address
    address public immutable entryPoint;

    /// @dev Nova Registry contract
    INovaRegistry public immutable novaRegistry;

    /// @dev Gas price markup percentage (basis points, e.g., 100 = 1%)
    uint256 public gasPriceMarkup;

    /**
     * @dev Emitted when gas is sponsored
     */
    event GasSponsored(address indexed appWallet, uint256 amount);

    /**
     * @dev Emitted when gas markup is updated
     */
    event GasPriceMarkupUpdated(uint256 oldMarkup, uint256 newMarkup);

    /**
     * @dev Error thrown when caller is not EntryPoint
     */
    error NotFromEntryPoint();

    /**
     * @dev Error thrown when app wallet is not registered
     */
    error WalletNotRegistered();

    /**
     * @dev Error thrown when insufficient gas budget
     */
    error InsufficientGasBudget();

    /**
     * @dev Modifier to check caller is EntryPoint
     */
    modifier onlyEntryPoint() {
        if (msg.sender != entryPoint) {
            revert NotFromEntryPoint();
        }
        _;
    }

    /**
     * @dev Constructor
     * @param _entryPoint EntryPoint contract address
     * @param _novaRegistry Nova Registry contract address
     * @param _admin Admin address
     */
    constructor(address _entryPoint, address _novaRegistry, address _admin) {
        require(_entryPoint != address(0) && _novaRegistry != address(0) && _admin != address(0), "Invalid parameters");

        entryPoint = _entryPoint;
        novaRegistry = INovaRegistry(_novaRegistry);
        gasPriceMarkup = 100; // 1% default markup

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
    }

    /**
     * @inheritdoc IPaymaster
     * @dev Validates if this paymaster will sponsor the operation
     */
    function validatePaymasterUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 maxCost)
        external
        override
        onlyEntryPoint
        returns (bytes memory context, uint256 validationData)
    {
        // Extract app contract address from paymasterAndData
        // Format: [paymaster_address(20)][app_contract(20)][...]
        if (userOp.paymasterAndData.length < 40) {
            return ("", 1); // Invalid paymaster data
        }

        // Extract app contract address from paymasterAndData
        // Format: [paymaster_address(20)][app_contract(20)][...]
        if (userOp.paymasterAndData.length < 40) {
            return ("", 1); // Invalid paymaster data
        }

        address appContract;
        // We can use slicing since we are in 0.8.x and it's calldata
        // bytes calldata paymasterAndData = userOp.paymasterAndData;
        // appContract = address(bytes20(paymasterAndData[20:40]));
        
        // Alternatively, to be safe and explicit:
        appContract = address(bytes20(userOp.paymasterAndData[20:40]));

        // Get app instance from registry
        INovaRegistry.AppInstance memory instance;
        try novaRegistry.getAppInstance(appContract) returns (INovaRegistry.AppInstance memory _instance) {
            instance = _instance;
        } catch {
            return ("", 1); // App not found
        }

        // Verify sender is the app's wallet
        if (userOp.sender != instance.walletAddress) {
            return ("", 1); // Unauthorized sender
        }

        // Check if app is active
        if (instance.status != INovaRegistry.InstanceStatus.Active) {
            return ("", 1); // App not active
        }

        // Calculate cost with markup
        uint256 costWithMarkup = maxCost + (maxCost * gasPriceMarkup / 10000);

        // Check gas budget
        if (instance.gasBudget < costWithMarkup) {
            return ("", 1); // Insufficient budget
        }

        // Pack context with app contract address and estimated cost
        context = abi.encode(appContract, costWithMarkup);

        // Return success
        validationData = 0;
    }

    /**
     * @inheritdoc IPaymaster
     * @dev Post-operation handler to deduct actual gas cost
     */
    function postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost, uint256 actualUserOpFeePerGas)
        external
        override
        onlyEntryPoint
    {
        // Decode context
        (address appContract, uint256 estimatedCost) = abi.decode(context, (address, uint256));

        // Calculate actual cost with markup
        uint256 actualCostWithMarkup = actualGasCost + (actualGasCost * gasPriceMarkup / 10000);

        // Deduct from app budget in registry
        try novaRegistry.deductGas(appContract, actualCostWithMarkup) {
            emit GasSponsored(appContract, actualCostWithMarkup);
        } catch {
            // If deduction fails, attempt with estimated cost as fallback
            try novaRegistry.deductGas(appContract, estimatedCost) {
                emit GasSponsored(appContract, estimatedCost);
            } catch {
                // Nothing we can do here, gas already spent
            }
        }
    }

    /**
     * @dev Set gas price markup
     * @param _gasPriceMarkup New markup in basis points (100 = 1%)
     */
    function setGasPriceMarkup(uint256 _gasPriceMarkup) external onlyRole(ADMIN_ROLE) {
        require(_gasPriceMarkup <= 1000, "Markup too high"); // Max 10%

        uint256 oldMarkup = gasPriceMarkup;
        gasPriceMarkup = _gasPriceMarkup;

        emit GasPriceMarkupUpdated(oldMarkup, _gasPriceMarkup);
    }

    /**
     * @dev Deposit ETH to EntryPoint for this paymaster
     */
    function deposit() external payable onlyRole(ADMIN_ROLE) {
        (bool success,) = entryPoint.call{value: msg.value}(abi.encodeWithSignature("depositTo(address)", address(this)));
        require(success, "Deposit failed");
    }

    /**
     * @dev Withdraw from EntryPoint
     * @param withdrawAddress Address to send funds
     * @param amount Amount to withdraw
     */
    function withdrawFromEntryPoint(address payable withdrawAddress, uint256 amount) external onlyRole(ADMIN_ROLE) {
        (bool success,) = entryPoint.call(
            abi.encodeWithSignature("withdrawTo(address,uint256)", withdrawAddress, amount)
        );
        require(success, "Withdraw failed");
    }

    /**
     * @dev Add stake to EntryPoint
     * @param unstakeDelaySec Unstake delay in seconds
     */
    function addStake(uint32 unstakeDelaySec) external payable onlyRole(ADMIN_ROLE) {
        (bool success,) =
            entryPoint.call{value: msg.value}(abi.encodeWithSignature("addStake(uint32)", unstakeDelaySec));
        require(success, "Add stake failed");
    }

    /**
     * @dev Receive function to accept ETH
     */
    receive() external payable {}
}
