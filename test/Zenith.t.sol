// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {Zenith} from "../src/Zenith.sol";

contract ZenithTest is Test {
    Zenith public target;

    uint256 sequencerKey = 123;

    event BlockSubmitted(uint256 indexed sequence, address indexed sequencer, uint32[] blobIndices);

    function setUp() public {
        target = new Zenith();
        target.grantRole(target.SEQUENCER_ROLE(), vm.addr(sequencerKey));
    }

    // BLOCKED by PR supporting vm.blobhashes: https://github.com/foundry-rs/foundry/pull/7001
    function BLOCKED_test_submitBlock() public {
        // first block has index 0
        uint256 blockSequence = 0;

        // construct array with fake blobhash
        bytes32[] memory blobHashes = new bytes32[](1);
        blobHashes[0] = bytes32("JUNK BLOBHASH");

        uint32[] memory blobIndices = new uint32[](1);
        blobIndices[0] = 0;

        // TODO: vm.blobhashes(blobHashes);

        // derive block commitment from sequence number and blobhashes
        bytes32 commit = target.blockCommitment(blockSequence, blobHashes);

        // sign block commitmenet with sequencer key 
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sequencerKey, commit);

        // should emit BlockSubmitted event
        vm.expectEmit();
        emit BlockSubmitted(0, vm.addr(sequencerKey), blobIndices);
        target.submitBlock(blockSequence, blobIndices, v, r, s);

        // should increment sequence number 
        assertEq(target.nextSequence(), blockSequence + 1);
    }

    // TODO: invalid sequencer 
    // TODO: invalid signature
    // TODO: incorrect sequence number
}
