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

    /// @dev This reproduces the admission blocker, not a passing launch-policy check. Art bytes must stay exact.
    function test_ExactLaunch2ArtIsRejectedByCurrentProtectedScan() public view {
        (uint256 count3,) = _scan(chunk3.code);
        (uint256 count4, uint256 first4) = _scan(chunk4.code);
        assertEq(count3, 0);
        assertEq(count4, 234);
        assertEq(first4, 3912);
        assertEq(uint8(chunk4.code[first4]), 0xf4);
    }

    /// @dev Audit finding for launch 3, reproduced without regenerating its art or hashes.
    function test_Chunk7AlsoHasTheReportedAdmissionBlocker() public {
        address chunk7 = factory.deploy(_initCode(7), bytes32(uint256(7)));
        (uint256 count, uint256 first) = _scan(chunk7.code);
        assertEq(count, 14);
        assertEq(first, 7671);
        assertEq(uint8(chunk7.code[first]), 0xf2);
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

    /// @dev The supplied protected floor's exact traversal, including PUSH immediates and bytes after STOP.
    function _scan(bytes memory code) private pure returns (uint256 count, uint256 first) {
        for (uint256 j; j < code.length; ++j) {
            uint8 op = uint8(code[j]);
            if (op >= 0x60 && op <= 0x7f) {
                j += op - 0x5f;
                continue;
            }
            if (op == 0xf4 || op == 0xf2 || op == 0xff) {
                if (count == 0) first = j;
                ++count;
            }
        }
    }
}
