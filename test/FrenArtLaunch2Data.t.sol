// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {FrenArtIndex} from "src/FrenArtIndex.sol";
import {FrenRenderer} from "src/FrenRenderer.sol";
import {ArtLaunchProbe} from "./FrenArtLaunch2.t.sol";

contract FrenArtLaunch2DataTest is Test {
    address[7] private chunks;
    FrenRenderer private renderer;
    string private constant ART = "script/art/data/";

    function setUp() public {
        ArtLaunchProbe factory = new ArtLaunchProbe();
        chunks[2] = factory.deploy(vm.getCode("FrenArtChunks.sol:FrenArtChunk3"), bytes32(uint256(3)));
        chunks[3] = factory.deploy(vm.getCode("FrenArtChunks.sol:FrenArtChunk4"), bytes32(uint256(4)));
        // Other launches are fixtures for checking the real consumer's validation.
        for (uint256 i; i < 7; ++i) {
            if (i != 2 && i != 3) {
                chunks[i] = deployCode(string.concat("FrenArtChunks.sol:FrenArtChunk", vm.toString(i + 1)));
            }
        }
        renderer = _deployRenderer(chunks);
    }

    function test_RendererUsesLaunch2ChunksInTheirSpecifiedSlots() public view {
        assertEq(renderer.chunk3(), chunks[2]);
        assertEq(renderer.chunk4(), chunks[3]);
    }

    /// @dev The checked-in binary layers are an oracle independent of the generated Solidity hex literals.
    function test_EveryLaunch2LayerMatchesItsOriginalBinaryAndCoversAllPayloadBytes() public view {
        string[] memory names = vm.parseJsonStringArray(vm.readFile(string.concat(ART, "manifest.json")), ".layers");
        bytes memory index = FrenArtIndex.INDEX;
        assertEq(names.length, FrenArtIndex.LAYERS);
        assertEq(index.length, (names.length + 1) * 5);
        uint256[2] memory covered;
        uint256[2] memory entries;
        for (uint256 i; i < names.length; ++i) {
            uint256 c = uint8(index[i * 5]);
            if (c != 2 && c != 3) continue;
            uint256 offset = _u16(index, i * 5 + 1);
            uint256 length = _u16(index, i * 5 + 3);
            assertGt(length, 0);
            assertEq(offset, covered[c - 2], "gap, overlap or reordered layer");
            assertLe(1 + offset + length, chunks[c].code.length, "layer outside runtime");
            bytes memory original = vm.readFileBinary(string.concat(ART, "layers/", names[i], ".bin"));
            assertEq(length, original.length, "wrong layer length");
            assertEq(_readCode(chunks[c], 1 + offset, length), original, names[i]);
            covered[c - 2] += length;
            ++entries[c - 2];
        }
        assertEq(entries[0], 12, "missing chunk 3 layers");
        assertEq(entries[1], 24, "missing chunk 4 layers");
        assertEq(covered[0] + 1, chunks[2].code.length, "unindexed chunk 3 bytes");
        assertEq(covered[1] + 1, chunks[3].code.length, "unindexed chunk 4 bytes");
    }

    function test_RendererRejectsSwappedOrDuplicatedLaunch2Chunks() public {
        address[7] memory bad = chunks;
        (bad[2], bad[3]) = (bad[3], bad[2]);
        _reject(bad);
        bad = chunks;
        bad[2] = chunks[3];
        _reject(bad);
        bad = chunks;
        bad[3] = chunks[2];
        _reject(bad);
    }

    function test_RendererRejectsMissingEOAAndOtherLaunchChunksInBothSlots() public {
        address eoa = makeAddr("no art");
        assertEq(eoa.code.length, 0);
        address[3] memory wrong = [address(0), eoa, chunks[0]];
        for (uint256 slot = 2; slot <= 3; ++slot) {
            for (uint256 i; i < wrong.length; ++i) {
                address[7] memory bad = chunks;
                bad[slot] = wrong[i];
                _reject(bad);
            }
        }
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_RendererRejectsAnySingleByteCorruption(bool fourth, uint256 byteSeed, uint8 maskSeed) public {
        address chunk = chunks[fourth ? 3 : 2];
        bytes memory code = chunk.code;
        uint256 offset = bound(byteSeed, 0, code.length - 1);
        uint8 mask = uint8(bound(maskSeed, 1, 255));
        code[offset] ^= bytes1(mask);
        vm.etch(chunk, code);
        _reject(chunks);
    }

    function test_RendererRejectsCorruptedFirstAndLastBytesEvenWithCorrectSize() public {
        for (uint256 slot = 2; slot <= 3; ++slot) {
            address chunk = chunks[slot];
            bytes memory code = chunk.code;
            code[0] ^= 0x01;
            vm.etch(chunk, code);
            _reject(chunks);
            code[0] ^= 0x01;
            code[code.length - 1] ^= 0x01;
            vm.etch(chunk, code);
            _reject(chunks);
            code[code.length - 1] ^= 0x01;
            vm.etch(chunk, code);
        }
    }

    function test_RendererRejectsTruncatedAndAppendedRuntime() public {
        for (uint256 slot = 2; slot <= 3; ++slot) {
            address chunk = chunks[slot];
            bytes memory original = chunk.code;
            bytes memory shortCode = _readCode(chunk, 0, original.length - 1);
            vm.etch(chunk, shortCode);
            _reject(chunks);
            vm.etch(chunk, bytes.concat(original, hex"00"));
            _reject(chunks);
            vm.etch(chunk, original);
        }
    }

    /// @dev Fault injection exercises the read bound after constructor validation.
    ///      Chunk code is immutable on chain; this is not an alleged mutation attack.
    function test_RendererReportsMissingWhenLaunch2DataIsUnavailableAtReadTime() public {
        bytes memory third = chunks[2].code;
        vm.etch(chunks[2], hex"00");
        vm.expectRevert(FrenRenderer.Missing.selector);
        renderer.canvas(2, 0); // Bobo's classic face lives in chunk 3.
        vm.etch(chunks[2], third);

        vm.etch(chunks[3], hex"00");
        vm.expectRevert(FrenRenderer.Missing.selector);
        renderer.canvas(0, 0); // Background 0 lives in chunk 4.
    }

    function _reject(address[7] memory bad) private {
        vm.expectRevert(FrenRenderer.BadArt.selector);
        _deployRenderer(bad);
    }

    function _deployRenderer(address[7] memory cs) private returns (FrenRenderer) {
        return new FrenRenderer(cs[0], cs[1], cs[2], cs[3], cs[4], cs[5], cs[6]);
    }

    function _u16(bytes memory data, uint256 offset) private pure returns (uint256) {
        return uint256(uint8(data[offset])) * 256 + uint8(data[offset + 1]);
    }

    function _readCode(address chunk, uint256 offset, uint256 length) private view returns (bytes memory data) {
        data = new bytes(length);
        assembly ("memory-safe") {
            extcodecopy(chunk, add(data, 32), offset, length)
        }
    }
}
