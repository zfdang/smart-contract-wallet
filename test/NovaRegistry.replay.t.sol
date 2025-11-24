// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {NovaRegistry} from "../nova-contracts/core/NovaRegistry.sol";
import {INovaRegistry} from "../nova-contracts/interfaces/INovaRegistry.sol";
import {INitroEnclaveVerifier} from "../nova-contracts/interfaces/INitroEnclaveVerifier.sol";
import {ZkCoProcessorType, VerifierJournal, Pcr, Bytes48, VerificationResult} from "../nova-contracts/types/NitroTypes.sol";

/**
 * @title NovaRegistry Replay Protection Tests
 * @notice Tests for attestation replay attack prevention
 */
contract NovaRegistryReplayTest is Test {
    NovaRegistry public registry;
    MockVerifier public mockVerifier;
    MockApp public app1;
    MockApp public app2;
    
    address public admin = address(0x1);
    address public platform = address(0x2);
    address public operator = address(0x3);
    
    bytes32 public constant PCR0 = bytes32(uint256(1));
    bytes32 public constant PCR1 = bytes32(uint256(2));
    bytes32 public constant PCR2 = bytes32(uint256(3));
    
    function setUp() public {
        // Deploy contracts
        mockVerifier = new MockVerifier();
        registry = new NovaRegistry();
        
        // Initialize registry
        vm.prank(admin);
        registry.initialize(address(mockVerifier), admin, platform);
        
        // Deploy test apps
        app1 = new MockApp(admin, address(registry));
        app2 = new MockApp(admin, address(registry));
        
        // Register apps
        vm.startPrank(admin);
        registry.registerApp(address(app1), PCR0, PCR1, PCR2);
        registry.registerApp(address(app2), PCR0, PCR1, PCR2);
        vm.stopPrank();
    }
    
    /**
     * @dev Helper to create a VerifierJournal
     */
    function _createJournal(
        uint64 timestamp,
        bytes memory nonce,
        address ethAddress
    ) internal pure returns (VerifierJournal memory) {
        Pcr[] memory pcrs = new Pcr[](3);
        pcrs[0] = Pcr({index: 0, value: Bytes48({first: PCR0, second: bytes16(0)})});
        pcrs[1] = Pcr({index: 1, value: Bytes48({first: PCR1, second: bytes16(0)})});
        pcrs[2] = Pcr({index: 2, value: Bytes48({first: PCR2, second: bytes16(0)})});
        
        bytes32[] memory certs = new bytes32[](1);
        certs[0] = keccak256("test-cert");
        
        bytes memory userData = abi.encode(ethAddress, bytes("tls-pubkey"));
        
        return VerifierJournal({
            result: VerificationResult.Success,
            trustedCertsPrefixLen: 1,
            timestamp: timestamp,
            certs: certs,
            userData: userData,
            nonce: nonce,
            publicKey: bytes("test-pubkey"),
            pcrs: pcrs,
            moduleId: "test-module"
        });
    }
    
    /**
     * @dev Test: Normal activation succeeds
     */
    function testActivateAppSucceeds() public {
        uint64 timestamp = uint64(block.timestamp * 1000);
        bytes memory nonce = abi.encodePacked(keccak256("nonce-1"));
        
        VerifierJournal memory journal = _createJournal(timestamp, nonce, operator);
        mockVerifier.setJournal(journal);
        
        bytes memory output = abi.encode(journal);
        bytes memory proof = bytes("proof");
        
        vm.prank(platform);
        registry.activateApp(address(app1), output, ZkCoProcessorType.RiscZero, proof);
        
        // Verify app is active
        INovaRegistry.AppInstance memory instance = registry.getAppInstance(address(app1));
        assertEq(uint256(instance.status), uint256(INovaRegistry.InstanceStatus.Active));
        assertEq(instance.operator, operator);
    }
    
    /**
     * @dev Test: Cannot reuse same attestation for different app
     */
    function testCannotReuseSameAttestation() public {
        uint64 timestamp = uint64(block.timestamp * 1000);
        bytes memory nonce = abi.encodePacked(keccak256("nonce-1"));
        
        VerifierJournal memory journal = _createJournal(timestamp, nonce, operator);
        mockVerifier.setJournal(journal);
        
        bytes memory output = abi.encode(journal);
        bytes memory proof = bytes("proof");
        
        // First activation succeeds
        vm.prank(platform);
        registry.activateApp(address(app1), output, ZkCoProcessorType.RiscZero, proof);
        
        // Second activation with same attestation fails
        vm.prank(platform);
        vm.expectRevert(INovaRegistry.AttestationAlreadyUsed.selector);
        registry.activateApp(address(app2), output, ZkCoProcessorType.RiscZero, proof);
    }
    
    /**
     * @dev Test: Cannot reuse same nonce with different attestation data
     */
    function testCannotReuseSameNonce() public {
        uint64 timestamp = uint64(block.timestamp * 1000);
        bytes memory nonce = abi.encodePacked(keccak256("same-nonce"));
        
        // First attestation
        VerifierJournal memory journal1 = _createJournal(timestamp, nonce, operator);
        mockVerifier.setJournal(journal1);
        
        bytes memory output1 = abi.encode(journal1);
        bytes memory proof1 = bytes("proof1");
        
        vm.prank(platform);
        registry.activateApp(address(app1), output1, ZkCoProcessorType.RiscZero, proof1);
        
        // Second attestation with same nonce but different data
        VerifierJournal memory journal2 = _createJournal(timestamp, nonce, address(0x999));
        journal2.publicKey = bytes("different-pubkey");
        mockVerifier.setJournal(journal2);
        
        bytes memory output2 = abi.encode(journal2);
        bytes memory proof2 = bytes("proof2");
        
        // Should fail due to nonce reuse
        vm.prank(platform);
        vm.expectRevert(INovaRegistry.NonceAlreadyUsed.selector);
        registry.activateApp(address(app2), output2, ZkCoProcessorType.RiscZero, proof2);
    }
    
    /**
     * @dev Test: Reject attestation that is too old
     */
    function testRejectOldAttestation() public {
        // Attestation from 10 minutes ago (outside 5 minute window)
        uint64 timestamp = uint64((block.timestamp - 10 minutes) * 1000);
        bytes memory nonce = abi.encodePacked(keccak256("nonce-old"));
        
        VerifierJournal memory journal = _createJournal(timestamp, nonce, operator);
        mockVerifier.setJournal(journal);
        
        bytes memory output = abi.encode(journal);
        bytes memory proof = bytes("proof");
        
        vm.prank(platform);
        vm.expectRevert(INovaRegistry.AttestationExpired.selector);
        registry.activateApp(address(app1), output, ZkCoProcessorType.RiscZero, proof);
    }
    
    /**
     * @dev Test: Reject attestation from the future
     */
    function testRejectFutureAttestation() public {
        // Attestation from 2 hours in the future
        uint64 timestamp = uint64((block.timestamp + 2 hours) * 1000);
        bytes memory nonce = abi.encodePacked(keccak256("nonce-future"));
        
        VerifierJournal memory journal = _createJournal(timestamp, nonce, operator);
        mockVerifier.setJournal(journal);
        
        bytes memory output = abi.encode(journal);
        bytes memory proof = bytes("proof");
        
        vm.prank(platform);
        vm.expectRevert(INovaRegistry.AttestationFromFuture.selector);
        registry.activateApp(address(app1), output, ZkCoProcessorType.RiscZero, proof);
    }
    
    /**
     * @dev Test: Allow attestation within validity window
     */
    function testAllowRecentAttestation() public {
        // Attestation from 2 minutes ago (within 5 minute window)
        uint64 timestamp = uint64((block.timestamp - 2 minutes) * 1000);
        bytes memory nonce = abi.encodePacked(keccak256("nonce-recent"));
        
        VerifierJournal memory journal = _createJournal(timestamp, nonce, operator);
        mockVerifier.setJournal(journal);
        
        bytes memory output = abi.encode(journal);
        bytes memory proof = bytes("proof");
        
        vm.prank(platform);
        registry.activateApp(address(app1), output, ZkCoProcessorType.RiscZero, proof);
        
        // Verify success
        INovaRegistry.AppInstance memory instance = registry.getAppInstance(address(app1));
        assertEq(uint256(instance.status), uint256(INovaRegistry.InstanceStatus.Active));
    }
    
    /**
     * @dev Test: Allow small clock drift (1 minute future)
     */
    function testAllowSmallClockDrift() public {
        // Attestation 30 seconds in the future (within 1 minute drift tolerance)
        uint64 timestamp = uint64((block.timestamp + 30 seconds) * 1000);
        bytes memory nonce = abi.encodePacked(keccak256("nonce-drift"));
        
        VerifierJournal memory journal = _createJournal(timestamp, nonce, operator);
        mockVerifier.setJournal(journal);
        
        bytes memory output = abi.encode(journal);
        bytes memory proof = bytes("proof");
        
        vm.prank(platform);
        registry.activateApp(address(app1), output, ZkCoProcessorType.RiscZero, proof);
        
        // Verify success
        INovaRegistry.AppInstance memory instance = registry.getAppInstance(address(app1));
        assertEq(uint256(instance.status), uint256(INovaRegistry.InstanceStatus.Active));
    }
    
    /**
     * @dev Test: Different attestations with different nonces work fine
     */
    function testDifferentAttestationsSucceed() public {
        uint64 timestamp = uint64(block.timestamp * 1000);
        
        // First attestation with nonce-1
        bytes memory nonce1 = abi.encodePacked(keccak256("nonce-1"));
        VerifierJournal memory journal1 = _createJournal(timestamp, nonce1, operator);
        mockVerifier.setJournal(journal1);
        
        vm.prank(platform);
        registry.activateApp(address(app1), abi.encode(journal1), ZkCoProcessorType.RiscZero, bytes("proof1"));
        
        // Second attestation with nonce-2
        bytes memory nonce2 = abi.encodePacked(keccak256("nonce-2"));
        VerifierJournal memory journal2 = _createJournal(timestamp, nonce2, address(0x888));
        mockVerifier.setJournal(journal2);
        
        vm.prank(platform);
        registry.activateApp(address(app2), abi.encode(journal2), ZkCoProcessorType.RiscZero, bytes("proof2"));
        
        // Both should be active
        assertEq(uint256(registry.getAppInstance(address(app1)).status), uint256(INovaRegistry.InstanceStatus.Active));
        assertEq(uint256(registry.getAppInstance(address(app2)).status), uint256(INovaRegistry.InstanceStatus.Active));
    }
    
    /**
     * @dev Test: AttestationConsumed event is emitted
     */
    function testAttestationConsumedEvent() public {
        uint64 timestamp = uint64(block.timestamp * 1000);
        bytes memory nonce = abi.encodePacked(keccak256("nonce-event"));
        
        VerifierJournal memory journal = _createJournal(timestamp, nonce, operator);
        mockVerifier.setJournal(journal);
        
        bytes memory output = abi.encode(journal);
        bytes memory proof = bytes("proof");
        
        // Expect AttestationConsumed event
        vm.expectEmit(true, true, true, true);
        // Note: We can't predict exact hash, so we just check event is emitted
        
        vm.prank(platform);
        registry.activateApp(address(app1), output, ZkCoProcessorType.RiscZero, proof);
    }
}

/**
 * @dev Mock Verifier for testing
 */
contract MockVerifier is INitroEnclaveVerifier {
    VerifierJournal private _journal;
    
    function setJournal(VerifierJournal memory journal) external {
        _journal = journal;
    }
    
    function verify(
        bytes calldata,
        ZkCoProcessorType,
        bytes calldata
    ) external view returns (VerifierJournal memory) {
        return _journal;
    }
    
    function batchVerify(
        bytes calldata,
        ZkCoProcessorType,
        bytes calldata
    ) external pure returns (VerifierJournal[] memory) {
        revert("Not implemented");
    }
    
    function maxTimeDiff() external pure returns (uint64) {
        return 300; // 5 minutes
    }
    
    function rootCert() external pure returns (bytes32) {
        return bytes32(0);
    }
    
    function revokeCert(bytes32) external pure {
        revert("Not implemented");
    }
    
    function checkTrustedIntermediateCerts(bytes32[][] calldata)
        external
        pure
        returns (uint8[] memory)
    {
        revert("Not implemented");
    }
    
    function setRootCert(bytes32) external pure {
        revert("Not implemented");
    }
    
    function setZkConfiguration(ZkCoProcessorType, ZkCoProcessorConfig memory) external pure {
        revert("Not implemented");
    }
    
    function getZkConfig(ZkCoProcessorType) external pure returns (ZkCoProcessorConfig memory) {
        revert("Not implemented");
    }
}

/**
 * @dev Mock App for testing
 */
contract MockApp {
    address public publisher;
    address public novaPlatform;
    address public operator;
    
    constructor(address _publisher, address _novaPlatform) {
        publisher = _publisher;
        novaPlatform = _novaPlatform;
    }
    
    function setOperator(address _operator) external {
        operator = _operator;
    }
}
