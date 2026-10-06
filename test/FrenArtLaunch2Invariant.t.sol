// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ArtLaunchProbe} from "./FrenArtLaunch2.t.sol";

/// @dev These are STOP-prefixed data contracts, not deposit accounts. Incidental ETH
///      can reach them, so track actual value movements without inventing withdrawal rights.
contract Launch2CallHandler is Test {
    uint256 public constant INITIAL_BALANCE = 1000 ether;
    address[2] public chunks;
    address[3] public actors;
    uint256[2] public received;
    uint256[3] public spent;
    uint256 public successfulCalls;
    uint256 public failedCalls;
    uint256 public staticCalls;

    constructor(address third, address fourth) {
        chunks = [third, fourth];
        actors = [address(0xA11CE), address(0xB0B), address(0xCA401)];
    }

    function callChunk(uint256 chunkSeed, uint256 actorSeed, uint256 amountSeed, bytes calldata payload) external {
        uint256 c = bound(chunkSeed, 0, 1);
        uint256 a = bound(actorSeed, 0, 2);
        uint256 limit = actors[a].balance < 1 ether ? actors[a].balance : 1 ether;
        uint256 amount = bound(amountSeed, 0, limit);
        bytes memory data = payload[:(payload.length < 512 ? payload.length : 512)];
        _record();
        vm.prank(actors[a]);
        (bool ok, bytes memory result) = chunks[c].call{value: amount}(data);
        assertTrue(ok, "STOP runtime call failed");
        assertEq(result.length, 0, "data bytes executed and returned a value");
        _assertNoStorageOrLogs(chunks[c]);
        received[c] += amount;
        spent[a] += amount;
        ++successfulCalls;
    }

    function staticProbe(uint256 chunkSeed, uint256 actorSeed, bytes calldata payload) external {
        address chunk = chunks[bound(chunkSeed, 0, 1)];
        address actor = actors[bound(actorSeed, 0, 2)];
        bytes memory data = payload[:(payload.length < 512 ? payload.length : 512)];
        _record();
        vm.prank(actor);
        (bool ok, bytes memory result) = chunk.staticcall(data);
        assertTrue(ok, "STOP runtime staticcall failed");
        assertEq(result.length, 0);
        _assertNoStorageOrLogs(chunk);
        ++staticCalls;
    }

    function insufficientFundsCall(uint256 chunkSeed, uint256 actorSeed) external {
        address chunk = chunks[bound(chunkSeed, 0, 1)];
        address actor = actors[bound(actorSeed, 0, 2)];
        uint256 amount = actor.balance + 1;
        _record();
        vm.prank(actor);
        (bool ok, bytes memory result) = chunk.call{value: amount}(hex"deadbeef");
        assertFalse(ok, "insufficient balance must fail before entering runtime");
        assertEq(result.length, 0);
        _assertNoStorageOrLogs(chunk);
        ++failedCalls;
    }

    function _record() private {
        vm.record();
        vm.recordLogs();
    }

    function _assertNoStorageOrLogs(address chunk) private {
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(chunk);
        assertEq(reads.length, 0, "data runtime read storage");
        assertEq(writes.length, 0, "data runtime wrote storage");
        assertEq(vm.getRecordedLogs().length, 0, "data runtime emitted logs");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract FrenArtLaunch2InvariantTest is Test {
    Launch2CallHandler private handler;
    address private third;
    address private fourth;

    function setUp() public {
        ArtLaunchProbe factory = new ArtLaunchProbe();
        third = factory.deploy(vm.getCode("FrenArtChunks.sol:FrenArtChunk3"), bytes32(uint256(3)));
        fourth = factory.deploy(vm.getCode("FrenArtChunks.sol:FrenArtChunk4"), bytes32(uint256(4)));
        handler = new Launch2CallHandler(third, fourth);
        for (uint256 i; i < 3; ++i) {
            vm.deal(handler.actors(i), handler.INITIAL_BALANCE());
        }
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = handler.callChunk.selector;
        selectors[1] = handler.staticProbe.selector;
        selectors[2] = handler.insufficientFundsCall.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_RuntimeRemainsExactAfterEveryCallSequence() public view {
        assertEq(third.codehash, 0xd73ecfd95e853d3bf20224d02e30889477ac2627bc1970c5e6b0ca5ef202c9a8);
        assertEq(fourth.codehash, 0x4412839e8ffb01f255ce07ec70fc6c55a67a78f4365ae2a71eaa4f4d8645a5aa);
        assertEq(third.code.length, 23_479);
        assertEq(fourth.code.length, 20_539);
    }

    function invariant_EthConservedAcrossActorsAndBothChunks() public view {
        assertEq(third.balance, handler.received(0), "chunk 3 differs from successful transfers");
        assertEq(fourth.balance, handler.received(1), "chunk 4 differs from successful transfers");
        uint256 total = third.balance + fourth.balance;
        uint256 totalSpent;
        for (uint256 i; i < 3; ++i) {
            address actor = handler.actors(i);
            assertEq(actor.balance + handler.spent(i), handler.INITIAL_BALANCE(), "actor gained or lost extra ETH");
            total += actor.balance;
            totalSpent += handler.spent(i);
        }
        assertEq(totalSpent, handler.received(0) + handler.received(1));
        assertEq(total, 3 * handler.INITIAL_BALANCE());
    }

    /// @dev Fixed edges complement random sequences and exercise every handler branch.
    function test_EmptyCalldataSelectorsAndValueEdges() public {
        for (uint256 c; c < 2; ++c) {
            handler.callChunk(c, 0, 0, hex"");
            handler.callChunk(c, 1, 1, hex"00");
            handler.callChunk(c, 2, 1 ether, abi.encodeWithSignature("initialize(address)", address(this)));
            handler.callChunk(c, 0, 0, abi.encodeWithSignature("withdraw()"));
            handler.callChunk(c, 1, 0, abi.encodeWithSignature("destroy(address)", address(this)));
            handler.callChunk(c, 2, 0, new bytes(512));
            handler.staticProbe(c, 0, hex"");
            handler.staticProbe(c, 1, hex"ffffffff");
            handler.insufficientFundsCall(c, 2);
        }
        assertEq(handler.successfulCalls(), 12);
        assertEq(handler.staticCalls(), 4);
        assertEq(handler.failedCalls(), 2);
        invariant_RuntimeRemainsExactAfterEveryCallSequence();
        invariant_EthConservedAcrossActorsAndBothChunks();
    }
}
