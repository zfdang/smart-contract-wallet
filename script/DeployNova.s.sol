// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {NovaRegistry} from "../nova-contracts/core/NovaRegistry.sol";
import {AppWalletFactory} from "../nova-contracts/core/AppWalletFactory.sol";
import {NovaPaymaster} from "../nova-contracts/core/NovaPaymaster.sol";
import {ExampleApp} from "../app-contracts/examples/ExampleApp.sol";

/**
 * @title DeployNova
 * @notice Deployment script for Nova TEE platform contracts
 * @dev Usage: forge script script/DeployNova.s.sol:DeployNova --rpc-url $RPC_URL --broadcast --verify
 */
contract DeployNova is Script {
    // Environment variables (set in .env)
    address nitroVerifier;
    address entryPoint;
    address admin;

    // Deployed contract addresses
    NovaRegistry public novaRegistryImpl;
    ERC1967Proxy public novaRegistryProxy;
    NovaRegistry public novaRegistry;
    AppWalletFactory public appWalletFactory;
    NovaPaymaster public novaPaymaster;
    ExampleApp public exampleApp;

    function setUp() public {
        // Load from environment or use defaults
        nitroVerifier = vm.envOr("NITRO_VERIFIER_ADDRESS", address(0));
        entryPoint = vm.envOr(
            "ENTRYPOINT_ADDRESS",
            0x0000000071727De22E5E9d8BAf0edAc6f37da032
        ); // AA v0.7
        admin = vm.envOr("ADMIN_ADDRESS", msg.sender);

        // Validate required addresses
        require(nitroVerifier != address(0), "NITRO_VERIFIER_ADDRESS not set");
        require(entryPoint != address(0), "ENTRYPOINT_ADDRESS not set");
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying Nova TEE Platform...");
        console.log("Deployer:", deployer);
        console.log("Admin:", admin);
        console.log("Nitro Verifier:", nitroVerifier);
        console.log("EntryPoint:", entryPoint);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy NovaRegistry Implementation
        console.log("1. Deploying NovaRegistry implementation...");
        novaRegistryImpl = new NovaRegistry();
        console.log(
            "   NovaRegistry Implementation:",
            address(novaRegistryImpl)
        );

        // 2. Deploy UUPS Proxy
        console.log("2. Deploying UUPS Proxy...");
        bytes memory initData = abi.encodeWithSelector(
            NovaRegistry.initialize.selector,
            nitroVerifier,
            admin,
            deployer
        );

        novaRegistryProxy = new ERC1967Proxy(
            address(novaRegistryImpl),
            initData
        );
        novaRegistry = NovaRegistry(address(novaRegistryProxy));
        console.log("   NovaRegistry Proxy:", address(novaRegistryProxy));

        // 3. Deploy AppWalletFactory
        console.log("3. Deploying AppWalletFactory...");
        appWalletFactory = new AppWalletFactory(
            entryPoint,
            address(novaRegistry)
        );
        console.log("   AppWalletFactory:", address(appWalletFactory));

        // 4. Deploy NovaPaymaster
        console.log("4. Deploying NovaPaymaster...");
        novaPaymaster = new NovaPaymaster(
            entryPoint,
            address(novaRegistry),
            admin
        );
        console.log("   NovaPaymaster:", address(novaPaymaster));

        // 5. Grant Paymaster Role
        console.log("5. Granting PAYMASTER_ROLE to NovaPaymaster...");
        bytes32 paymasterRole = novaRegistry.PAYMASTER_ROLE();
        novaRegistry.grantRole(paymasterRole, address(novaPaymaster));
        console.log("   PAYMASTER_ROLE granted");

        // 6. Deploy Example App (optional)
        console.log("6. Deploying ExampleApp...");
        exampleApp = new ExampleApp(deployer, address(novaRegistry));
        console.log("   ExampleApp:", address(exampleApp));

        vm.stopBroadcast();

        // Print deployment summary
        console.log("");
        console.log("=== Deployment Summary ===");
        console.log("NovaRegistry (Proxy):", address(novaRegistry));
        console.log("NovaRegistry (Impl):", address(novaRegistryImpl));
        console.log("AppWalletFactory:", address(appWalletFactory));
        console.log("NovaPaymaster:", address(novaPaymaster));
        console.log("ExampleApp:", address(exampleApp));
        console.log("");
        console.log("Next steps:");
        console.log(
            "1. Fund Paymaster: cast send",
            address(novaPaymaster),
            '"deposit()" --value 0.1ether'
        );
        console.log(
            "2. Initialize ExampleApp: cast send",
            address(exampleApp),
            '"initialize(bytes32,bytes32,bytes32)" <pcr0> <pcr1> <pcr2>'
        );
        console.log(
            "3. Register ExampleApp: cast send",
            address(novaRegistry),
            '"registerApp(address,bytes32,bytes32,bytes32)"',
            address(exampleApp),
            "<pcr0> <pcr1> <pcr2>"
        );
    }
}
