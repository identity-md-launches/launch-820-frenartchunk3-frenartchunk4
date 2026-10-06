// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FrenArtIndex} from "../src/FrenArtIndex.sol";

/// @dev Test-only CREATE2 probe; deployment sends no value except in the constructor rejection test.
contract ArtLaunchProbe {
    function deploy(bytes memory code, bytes32 salt) external payable returns (address deployed) {
        require(code.length > 0 && code.length <= 49_152, "invalid init code");
        assembly ("memory-safe") {
            deployed := create2(callvalue(), add(code, 32), mload(code), salt)
        }
        require(deployed != address(0), "application constructor failed");
    }
}

contract FrenArtLaunch2Test is Test {
    ArtLaunchProbe private factory;
    address private chunk3;
    address private chunk4;

    function setUp() public {
        factory = new ArtLaunchProbe();
        // The requested order, with creation code only: neither constructor takes arguments.
        chunk3 = factory.deploy(_initCode(3), bytes32(uint256(3)));
        chunk4 = factory.deploy(_initCode(4), bytes32(uint256(4)));
    }

    function test_Launch2PreservesExactRuntimeAndFactoryAddresses() public view {
        _checkChunk(chunk3, 3, 23_479, 0xd73ecfd95e853d3bf20224d02e30889477ac2627bc1970c5e6b0ca5ef202c9a8);
        _checkChunk(chunk4, 4, 20_539, 0x4412839e8ffb01f255ce07ec70fc6c55a67a78f4365ae2a71eaa4f4d8645a5aa);
    }

    function test_Launch2ConstructorsRejectValue() public {
        vm.deal(address(this), 2 wei);
        for (uint256 n = 3; n <= 4; ++n) {
            bytes memory code = _initCode(n);
            vm.expectRevert(bytes("application constructor failed"));
            factory.deploy{value: 1 wei}(code, bytes32(n + 10));
        }
    }

    // Admission-scan failures are reported in .imd-findings.json with a failing proof,
    // rather than requiring the known blocker to persist in a passing regression test.

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_NonzeroDeploymentValueRollsBackAndSaltCanBeRetried(uint256 valueSeed, uint256 saltSeed) public {
        uint256 amount = bound(valueSeed, 1, type(uint256).max);
        bytes32 salt = bytes32(bound(saltSeed, 5, type(uint256).max));
        _rejectValueAndRetry(3, amount, salt);
        _rejectValueAndRetry(4, amount, salt);
    }

    function test_DeploymentValueBoundaries() public {
        for (uint256 n = 3; n <= 4; ++n) {
            _rejectValueAndRetry(n, 1, bytes32(uint256(100)));
            _rejectValueAndRetry(n, type(uint256).max, bytes32(uint256(101)));
        }
    }

    function test_DuplicateCreate2CannotReplaceEitherChunk() public {
        uint64 nonceBefore = vm.getNonce(address(factory));
        for (uint256 n = 3; n <= 4; ++n) {
            bytes memory code = _initCode(n);
            vm.expectRevert(bytes("application constructor failed"));
            factory.deploy{gas: 8_000_000}(code, bytes32(n));
        }
        assertEq(vm.getNonce(address(factory)), nonceBefore, "failed factory call must roll back its nonce");
        test_Launch2PreservesExactRuntimeAndFactoryAddresses();
    }

    function test_SameSaltForDifferentChunksProducesDistinctCorrectAddresses() public {
        bytes32 salt = bytes32(uint256(102));
        address third = factory.deploy(_initCode(3), salt);
        address fourth = factory.deploy(_initCode(4), salt);
        assertNotEq(third, fourth);
        assertEq(third, computeCreate2Address(salt, keccak256(_initCode(3)), address(factory)));
        assertEq(fourth, computeCreate2Address(salt, keccak256(_initCode(4)), address(factory)));
        assertEq(third.codehash, chunk3.codehash);
        assertEq(fourth.codehash, chunk4.codehash);
    }

    function test_ZeroValueDeploymentWorksAtPrefundedAddresses() public {
        for (uint256 n = 3; n <= 4; ++n) {
            bytes memory code = _initCode(n);
            bytes32 salt = bytes32(uint256(103));
            address predicted = computeCreate2Address(salt, keccak256(code), address(factory));
            vm.deal(predicted, 1 ether);
            assertEq(predicted.code.length, 0);
            address deployed = factory.deploy(code, salt);
            assertEq(deployed, predicted);
            assertEq(deployed.balance, 1 ether);
            assertEq(deployed.codehash, (n == 3 ? chunk3 : chunk4).codehash);
        }
    }

    function test_RejectedDeploymentPreservesPrefundingAndCanBeRetried() public {
        for (uint256 n = 3; n <= 4; ++n) {
            bytes memory code = _initCode(n);
            bytes32 salt = bytes32(uint256(104));
            address predicted = computeCreate2Address(salt, keccak256(code), address(factory));
            vm.deal(predicted, 1 ether);
            vm.deal(address(this), 1 wei);
            uint64 nonceBefore = vm.getNonce(address(factory));

            vm.expectRevert(bytes("application constructor failed"));
            factory.deploy{value: 1 wei}(code, salt);

            assertEq(predicted.code.length, 0, "failed constructor left runtime");
            assertEq(vm.getNonce(predicted), 0, "failed constructor left a creation nonce");
            assertEq(predicted.balance, 1 ether, "failed constructor changed prefunding");
            assertEq(address(this).balance, 1 wei, "deployment value not refunded");
            assertEq(address(factory).balance, 0, "factory retained value");
            assertEq(vm.getNonce(address(factory)), nonceBefore, "factory nonce not rolled back");

            assertEq(factory.deploy(code, salt), predicted, "failed attempt consumed salt");
            assertEq(predicted.balance, 1 ether, "retry changed prefunding");
            assertEq(predicted.codehash, (n == 3 ? chunk3 : chunk4).codehash);
        }
    }

    /// @dev STOP succeeds even with value. Preserving these data contracts preserves this documented ETH sink.
    function test_Launch2RetainsDocumentedEthSink() public {
        vm.deal(address(this), 2 ether);
        address[2] memory chunks = [chunk3, chunk4];
        for (uint256 i; i < chunks.length; ++i) {
            bytes32 originalHash = chunks[i].codehash;
            (bool ok, bytes memory result) = chunks[i].call{value: 1 ether}(hex"deadbeef");
            assertTrue(ok);
            assertEq(result.length, 0);
            assertEq(chunks[i].balance, 1 ether);
            (ok, result) = chunks[i].call(abi.encodeWithSignature("withdraw()"));
            assertTrue(ok);
            assertEq(result.length, 0);
            assertEq(chunks[i].balance, 1 ether);
            assertEq(chunks[i].codehash, originalHash);
        }
    }

    function _initCode(uint256 n) private view returns (bytes memory) {
        return vm.getCode(string.concat("FrenArtChunks.sol:FrenArtChunk", vm.toString(n)));
    }

    function _rejectValueAndRetry(uint256 n, uint256 amount, bytes32 salt) private {
        bytes memory code = _initCode(n);
        address predicted = computeCreate2Address(salt, keccak256(code), address(factory));
        uint64 nonceBefore = vm.getNonce(address(factory));
        vm.deal(address(this), amount);

        vm.expectRevert(bytes("application constructor failed"));
        factory.deploy{value: amount}(code, salt);

        assertEq(predicted.code.length, 0, "failed constructor left runtime");
        assertEq(predicted.balance, 0, "failed constructor retained value");
        assertEq(address(this).balance, amount, "deployment value not refunded");
        assertEq(address(factory).balance, 0, "factory retained value");
        assertEq(vm.getNonce(address(factory)), nonceBefore, "factory nonce not rolled back");
        assertEq(factory.deploy(code, salt), predicted, "failed attempt consumed salt");
        assertEq(predicted.codehash, (n == 3 ? chunk3 : chunk4).codehash);
    }

    function _checkChunk(address chunk, uint256 n, uint256 size, bytes32 hash) private view {
        bytes memory code = _initCode(n);
        assertLe(code.length, 49_152);
        address predicted = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), bytes32(n), keccak256(code)))))
        );
        assertEq(chunk, predicted);
        assertEq(chunk.code.length, size);
        assertLe(size, 24_576);
        assertEq(chunk.codehash, hash);
        assertEq(uint8(chunk.code[0]), 0x00);
        bytes memory hashes = FrenArtIndex.CHUNK_HASHES;
        bytes32 indexedHash;
        assembly ("memory-safe") {
            indexedHash := mload(add(hashes, mul(n, 32)))
        }
        assertEq(hash, indexedHash);
        bytes memory sizes = FrenArtIndex.CHUNK_SIZES;
        assertEq(size, uint256(uint8(sizes[(n - 1) * 2])) * 256 + uint8(sizes[(n - 1) * 2 + 1]));
    }
}
