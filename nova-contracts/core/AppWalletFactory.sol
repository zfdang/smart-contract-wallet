// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {AppWallet} from "../account/AppWallet.sol";
import {INovaRegistry} from "../interfaces/INovaRegistry.sol";

/**
 * @title AppWalletFactory
 * @notice Factory contract for deploying EIP-4337 smart contract wallets for apps
 * @dev Uses CREATE2 for deterministic wallet addresses
 */
contract AppWalletFactory {
    /// @dev EntryPoint contract address
    address public immutable entryPoint;

    /// @dev Nova Registry contract
    INovaRegistry public immutable novaRegistry;

    /// @dev Mapping of app contract to deployed wallet
    mapping(address => address) public appWallets;

    /**
     * @dev Emitted when a new wallet is created
     */
    event WalletCreated(address indexed appContract, address indexed wallet, address indexed operator);

    /**
     * @dev Error thrown when wallet already exists
     */
    error WalletAlreadyExists();

    /**
     * @dev Error thrown when parameters are invalid
     */
    error InvalidParameters();

    /**
     * @dev Constructor
     * @param _entryPoint EntryPoint contract address
     * @param _novaRegistry Nova Registry contract address
     */
    constructor(address _entryPoint, address _novaRegistry) {
        if (_entryPoint == address(0) || _novaRegistry == address(0)) {
            revert InvalidParameters();
        }

        entryPoint = _entryPoint;
        novaRegistry = INovaRegistry(_novaRegistry);
    }

    /**
     * @dev Create a new app wallet
     * @param appContract App contract address
     * @param operator Initial operator address
     * @param salt Salt for CREATE2
     * @return wallet Address of created wallet
     */
    function createWallet(address appContract, address operator, bytes32 salt) external returns (address wallet) {
        if (appContract == address(0) || operator == address(0)) {
            revert InvalidParameters();
        }

        if (appWallets[appContract] != address(0)) {
            revert WalletAlreadyExists();
        }

        // Deploy wallet using CREATE2
        wallet = address(
            new AppWallet{salt: salt}(
                entryPoint,
                address(novaRegistry),
                appContract,
                operator
            )
        );

        appWallets[appContract] = wallet;

        emit WalletCreated(appContract, wallet, operator);

        return wallet;
    }

    /**
     * @dev Compute the address of a wallet before deployment
     * @param appContract App contract address
     * @param operator Operator address
     * @param salt Salt for CREATE2
     * @return Address where wallet will be deployed
     */
    function getWalletAddress(address appContract, address operator, bytes32 salt)
        external
        view
        returns (address)
    {
        bytes memory bytecode = abi.encodePacked(
            type(AppWallet).creationCode,
            abi.encode(entryPoint, address(novaRegistry), appContract, operator)
        );

        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));

        return address(uint160(uint256(hash)));
    }

    /**
     * @dev Get wallet for app contract
     * @param appContract App contract address
     * @return Wallet address (zero if not deployed)
     */
    function getWallet(address appContract) external view returns (address) {
        return appWallets[appContract];
    }
}
