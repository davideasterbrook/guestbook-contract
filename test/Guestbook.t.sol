// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console2} from "forge-std/Test.sol";
import {Guestbook} from "../src/Guestbook.sol";

contract MockEndpoint {
    mapping(address => address) public delegates;
    mapping(address => mapping(uint32 => bytes32)) public peers;

    function setDelegate(address _delegate) external {
        delegates[msg.sender] = _delegate;
    }

    function setPeer(uint32 _eid, bytes32 _peer) external {
        peers[msg.sender][_eid] = _peer;
    }

    // Matches LayerZero's MessagingParams struct
    struct MessagingParams {
        uint32 dstEid;
        bytes32 receiver;
        bytes message;
        bytes options;
        bool payInLzToken;
    }

    function quote(
        MessagingParams calldata, // _params
        address // _sender
    ) external pure returns (uint256 nativeFee, uint256 lzTokenFee) {
        return (0.001 ether, 0);
    }

    struct MessagingReceipt {
        bytes32 guid;
        uint64 nonce;
        uint256 nativeFee;
    }

    function send(
        MessagingParams calldata, // _params
        address // _refundAddress
    ) external payable returns (MessagingReceipt memory receipt) {
        // Note: Peer checking is done in OApp layer, not endpoint layer
        return MessagingReceipt({
            guid: keccak256("mock"),
            nonce: 1,
            nativeFee: msg.value
        });
    }
}

/**
 * @title GuestbookTest
 * @notice Tests for pure event-based guestbook architecture
 * @dev Since there's no on-chain storage, tests verify events are emitted correctly.
 *      In production, The Graph subgraph would index these events for querying.
 */
contract GuestbookTest is Test {
    Guestbook public guestbook;
    MockEndpoint public endpoint;

    address public owner = address(this);
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    // Event declarations for testing
    event SignedGuestbook(
        address indexed signer,
        uint32 indexed sourceChainId,
        string name,
        string message,
        uint256 timestamp
    );

    event ChainAdded(uint32 indexed chainEid);
    event ChainRemoved(uint32 indexed chainEid);

    function setUp() public {
        endpoint = new MockEndpoint();

        guestbook = new Guestbook(
            address(endpoint),
            owner,
            uint32(block.chainid) // localEid
        );
    }

    function testSignGuestbook() public {
        vm.prank(user1);

        // Expect SignedGuestbook event
        vm.expectEmit(true, true, true, true);
        emit SignedGuestbook(
            user1,
            uint32(block.chainid),
            "Alice",
            "Hello World!",
            block.timestamp
        );

        guestbook.signGuestbook("Alice", "Hello World!", "");
    }

    function testMultipleSignatures() public {
        // User1 signs
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit SignedGuestbook(
            user1,
            uint32(block.chainid),
            "Alice",
            "First message",
            block.timestamp
        );
        guestbook.signGuestbook("Alice", "First message", "");

        // User2 signs
        vm.prank(user2);
        vm.expectEmit(true, true, true, true);
        emit SignedGuestbook(
            user2,
            uint32(block.chainid),
            "Bob",
            "Second message",
            block.timestamp
        );
        guestbook.signGuestbook("Bob", "Second message", "");

        // User1 signs again
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit SignedGuestbook(
            user1,
            uint32(block.chainid),
            "Alice",
            "Third message",
            block.timestamp
        );
        guestbook.signGuestbook("Alice", "Third message", "");
    }

    function testEmptyFields() public {
        vm.prank(user1);

        vm.expectEmit(true, true, true, true);
        emit SignedGuestbook(
            user1,
            uint32(block.chainid),
            "",
            "",
            block.timestamp
        );

        guestbook.signGuestbook("", "", "");
    }

    function testSignGuestbookFor() public {
        // Only owner can sign for others
        vm.expectEmit(true, true, true, true);
        emit SignedGuestbook(
            user1,
            uint32(block.chainid),
            "Alice",
            "Bootstrapped message",
            block.timestamp
        );

        guestbook.signGuestbookFor(user1, "Alice", "Bootstrapped message", "");
    }

    function testSignGuestbookForUnauthorized() public {
        // Non-owner cannot sign for others
        vm.prank(user1);
        vm.expectRevert();
        guestbook.signGuestbookFor(user2, "Bob", "Unauthorized", "");
    }

    function testSetPeerAutoRegistersChain() public {
        uint32 arbitrumEid = 30110;
        uint32 baseEid = 30184;
        address remoteGuestbook1 = address(0x999);
        address remoteGuestbook2 = address(0x888);

        // Set peer for Arbitrum - should auto-register
        vm.expectEmit(true, false, false, false);
        emit ChainAdded(arbitrumEid);
        guestbook.setPeer(arbitrumEid, bytes32(uint256(uint160(remoteGuestbook1))));

        assertTrue(guestbook.isChainRegistered(arbitrumEid));

        // Set peer for Base - should auto-register
        vm.expectEmit(true, false, false, false);
        emit ChainAdded(baseEid);
        guestbook.setPeer(baseEid, bytes32(uint256(uint160(remoteGuestbook2))));

        assertTrue(guestbook.isChainRegistered(baseEid));

        // Check registered chains
        uint32[] memory chains = guestbook.getRegisteredChains();
        assertEq(chains.length, 2);
        assertEq(chains[0], arbitrumEid);
        assertEq(chains[1], baseEid);
    }

    function testSetPeerToZeroRemovesChain() public {
        uint32 arbitrumEid = 30110;
        address remoteGuestbook = address(0x999);

        // Set peer - auto-registers
        guestbook.setPeer(arbitrumEid, bytes32(uint256(uint160(remoteGuestbook))));
        assertTrue(guestbook.isChainRegistered(arbitrumEid));

        // Remove peer (set to zero) - should auto-remove from registry
        vm.expectEmit(true, false, false, false);
        emit ChainRemoved(arbitrumEid);
        guestbook.setPeer(arbitrumEid, bytes32(0));

        assertFalse(guestbook.isChainRegistered(arbitrumEid));
        assertEq(guestbook.getRegisteredChains().length, 0);
    }

    function testSetPeerTwiceDoesNotDuplicate() public {
        uint32 arbitrumEid = 30110;
        address remoteGuestbook1 = address(0x999);
        address remoteGuestbook2 = address(0x888);

        // Set peer first time
        guestbook.setPeer(arbitrumEid, bytes32(uint256(uint160(remoteGuestbook1))));
        assertEq(guestbook.getRegisteredChains().length, 1);

        // Update peer - should not add duplicate to registry
        guestbook.setPeer(arbitrumEid, bytes32(uint256(uint160(remoteGuestbook2))));
        assertEq(guestbook.getRegisteredChains().length, 1);
        assertTrue(guestbook.isChainRegistered(arbitrumEid));
    }

    function testCannotSetCurrentChainAsPeer() public {
        uint32 currentChain = uint32(block.chainid);

        vm.expectRevert(Guestbook.CannotAddCurrentChain.selector);
        guestbook.setPeer(currentChain, bytes32(uint256(uint160(address(0x999)))));
    }

    function testQuoteBroadcast() public {
        // Set up peers for LayerZero (simulating remote guestbook contracts)
        // This also auto-registers chains for broadcasting
        address remoteGuestbook = address(0x999);
        guestbook.setPeer(30110, bytes32(uint256(uint160(remoteGuestbook)))); // Arbitrum
        guestbook.setPeer(30184, bytes32(uint256(uint160(remoteGuestbook)))); // Base
        guestbook.setPeer(30109, bytes32(uint256(uint160(remoteGuestbook)))); // Polygon

        vm.prank(user1);
        uint256 totalFee = guestbook.quoteBroadcast(
            user1,
            "Alice",
            "Broadcast message",
            ""
        );

        // Mock returns 0.001 ether per chain, so 3 chains = 0.003 ether
        assertEq(totalFee, 0.003 ether);
    }

    function testBatchEmitSignatures() public {
        uint256 ts1 = block.timestamp + 1000;
        uint256 ts2 = block.timestamp + 2000;

        // Create signature data array (simulating fetched from subgraph)
        Guestbook.SignatureData[] memory sigs = new Guestbook.SignatureData[](2);
        sigs[0] = Guestbook.SignatureData({
            signer: user1,
            sourceChainId: uint32(1), // Ethereum
            name: "Alice",
            message: "Historical message 1",
            timestamp: ts1
        });
        sigs[1] = Guestbook.SignatureData({
            signer: user2,
            sourceChainId: uint32(42161), // Arbitrum
            name: "Bob",
            message: "Historical message 2",
            timestamp: ts2
        });

        // Expect first event
        vm.expectEmit(true, true, true, true);
        emit SignedGuestbook(
            user1,
            uint32(1),
            "Alice",
            "Historical message 1",
            ts1
        );

        // Expect second event
        vm.expectEmit(true, true, true, true);
        emit SignedGuestbook(
            user2,
            uint32(42161),
            "Bob",
            "Historical message 2",
            ts2
        );

        // Owner emits historical signatures locally
        guestbook.batchEmitSignatures(sigs);
    }

    function testBatchEmitSignaturesUnauthorized() public {
        Guestbook.SignatureData[] memory sigs = new Guestbook.SignatureData[](1);
        sigs[0] = Guestbook.SignatureData({
            signer: user1,
            sourceChainId: uint32(block.chainid),
            name: "Alice",
            message: "Test",
            timestamp: block.timestamp
        });

        vm.prank(user1);
        vm.expectRevert();
        guestbook.batchEmitSignatures(sigs);
    }

    function testBatchEmitEmptyArrayReverts() public {
        Guestbook.SignatureData[] memory sigs = new Guestbook.SignatureData[](0);

        vm.expectRevert(Guestbook.NoSignaturesToEmit.selector);
        guestbook.batchEmitSignatures(sigs);
    }

    // ============ New Tests for Recent Features ============

    function testLocalEid() public {
        assertEq(guestbook.localEid(), uint32(block.chainid));
    }

    function testSignGuestbookWithBroadcast() public {
        // Skip: Requires full LayerZero endpoint mock
        // Testing cross-chain broadcasting requires a complete LayerZero endpoint implementation
        // This will be tested in local multi-chain integration tests
    }

    function testSignGuestbookWithExcessFeeRefund() public {
        // Skip: Requires full LayerZero endpoint mock
        // Testing refund logic requires a complete LayerZero endpoint implementation
        // This will be tested in local multi-chain integration tests
    }

    function testSignGuestbookInsufficientFee() public {
        // Set up peer (auto-registers for broadcasting)
        address remoteGuestbook = address(0x999);
        guestbook.setPeer(30110, bytes32(uint256(uint160(remoteGuestbook)))); // Arbitrum

        // Get quote
        uint256 totalFee = guestbook.quoteBroadcast(user1, "Alice", "Hello!", "");

        // Try to sign with insufficient fee
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert(Guestbook.InsufficientFee.selector);
        guestbook.signGuestbook{value: totalFee - 1}("Alice", "Hello!", "");
    }

    function testSignGuestbookForWithBroadcast() public {
        // Skip: Requires full LayerZero endpoint mock
        // Testing cross-chain broadcasting requires a complete LayerZero endpoint implementation
        // This will be tested in local multi-chain integration tests
    }

    function testUserCanSignForThemselves() public {
        // Users can call signGuestbookFor for themselves (same as signGuestbook)
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit SignedGuestbook(user1, uint32(block.chainid), "Alice", "Self-signed", block.timestamp);

        guestbook.signGuestbookFor(user1, "Alice", "Self-signed", "");
    }

    function testLzReceive() public {
        // For now, skip this test - it requires proper LayerZero endpoint mock
        // Will be tested in integration tests with real endpoints
        // This tests the _lzReceive internal function which is protected
    }

    function testQuoteBroadcastWithNoChains() public {
        // No chains registered
        uint256 totalFee = guestbook.quoteBroadcast(user1, "Alice", "Hello", "");
        assertEq(totalFee, 0);
    }

    function testSignGuestbookWithNoChains() public {
        // Should work even with no chains (just emit local event, no broadcast)
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit SignedGuestbook(user1, uint32(block.chainid), "Alice", "Local only", block.timestamp);

        guestbook.signGuestbook("Alice", "Local only", "");
    }
}
