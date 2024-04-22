// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {Zenith} from "../src/Zenith.sol";

contract ZenithTest is Test {
    Zenith public target;

    Zenith.BlockHeader header;
    bytes32[] blobHashes;
    uint32[] blobIndices;
    bytes32 commit;

    uint256 sequencerKey = 123;
    uint256 notSequencerKey = 300;

    event BlockSubmitted(Zenith.DataLocation indexed location, address indexed sequencer, Zenith.BlockHeader indexed header);

    function setUp() public {
        target = new Zenith(address(this));
        target.grantRole(target.SEQUENCER_ROLE(), vm.addr(sequencerKey));

        // set default block values
        header.rollupChainId = block.chainid + 1;
        header.sequence = 0; // first block has index
        header.confirmBy = block.timestamp + 10 minutes;
        header.gasLimit = 30_000_000;
        header.rewardAddress = address(this);

        // set default blob info
        blobIndices.push(0);
        blobHashes.push(bytes32("JUNK BLOBHASH"));
        // TODO: vm.blobhashes(blobHashes);

        // derive block commitment from sequence number and blobhashes
        commit = target.blockCommitment(header, packHashes(blobHashes));
    }

    /// @notice Encode the array of blob hashes into a bytes string.
    /// @param _blobHashes - the 4844 blob hashes for the block data.
    /// @return encodedHashes - the encoded blob hashes.
    function packHashes(bytes32[] memory _blobHashes) public pure returns (bytes memory encodedHashes) {
        for (uint32 i = 0; i < _blobHashes.length; i++) {
            encodedHashes = abi.encodePacked(encodedHashes, _blobHashes[i]);
        }
    }

    // cannot submit block with incorrect sequence number
    function test_badSequence() public {
        // change to incorrect sequence number
        header.sequence = 1;

        // sign block commitmenet with sequencer key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sequencerKey, commit);

        vm.expectRevert(abi.encodeWithSelector(Zenith.BadSequence.selector, 0));
        target.submitBlock(header, blobIndices, v, r, s);
    }

    // cannot submit block with expired confirmBy time
    function test_blockExpired() public {
        // change to expired confirmBy time
        header.confirmBy = block.timestamp - 1;

        // sign block commitmenet with sequencer key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sequencerKey, commit);

        vm.expectRevert(abi.encodeWithSelector(Zenith.BlockExpired.selector));
        target.submitBlock(header, blobIndices, v, r, s);
    }

    // BLOCKED by PR supporting vm.blobhashes: https://github.com/foundry-rs/foundry/pull/7001
    // can submit block successfully with acceptable data & correct signature provided
    function BLOCKED_test_submitBlock() public {
        // sign block commitmenet with correct sequencer key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sequencerKey, commit);

        // should emit BlockSubmitted event
        vm.expectEmit();
        emit BlockSubmitted(Zenith.DataLocation.Blobs, vm.addr(sequencerKey), header);
        target.submitBlock(header, blobIndices, v, r, s);

        // should increment sequence number
        assertEq(target.nextSequence(header.rollupChainId), header.sequence + 1);
    }

    // cannot submit block with invalid sequencer signer from non-permissioned key
    function BLOCKED_test_notSequencer() public {
        // sign block commitmenet with NOT sequencer key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(notSequencerKey, commit);

        vm.expectRevert(abi.encodeWithSelector(Zenith.BadSignature.selector, vm.addr(notSequencerKey)));
        target.submitBlock(header, blobIndices, v, r, s);
    }

    // cannot submit block with sequencer signature over different block header data
    function BLOCKED_test_badSignature_header() public {
        // sign original block commitmenet with sequencer key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sequencerKey, commit);

        // change header data from what was signed by sequencer
        header.confirmBy = block.timestamp + 15 minutes;

        bytes32 newCommit = target.blockCommitment(header, packHashes(blobHashes));
        address derivedSigner = ecrecover(newCommit, v, r, s);

        vm.expectRevert(abi.encodeWithSelector(Zenith.BadSignature.selector, derivedSigner));
        target.submitBlock(header, blobIndices, v, r, s);
    }

    // cannot submit block with sequencer signature over different blob hashes
    function BLOCKED_test_badSignature_blobs() public {
        // sign original block commitmenet with sequencer key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sequencerKey, commit);

        blobHashes[0] = bytes32("DIFFERENT BLOBHASH");
        // TODO: vm.blobhashes(blobHashes);

        bytes32 newCommit = target.blockCommitment(header, packHashes(blobHashes));
        address derivedSigner = ecrecover(newCommit, v, r, s);

        vm.expectRevert(abi.encodeWithSelector(Zenith.BadSignature.selector, derivedSigner));
        target.submitBlock(header, blobIndices, v, r, s);
    }
}
