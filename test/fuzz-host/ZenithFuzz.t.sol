// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.26;

// test contracts
import {Zenith} from "../../src/Zenith.sol";
// utils
import {SignetStdTest} from "../SignetStdTest.t.sol";
import {Test, console2} from "forge-std/Test.sol";

contract ZenithFuzzTest is SignetStdTest {
    Zenith public target;

    uint256 sequencerKey = 123;

    event BlockSubmitted(
        address indexed sequencer,
        uint256 indexed rollupChainId,
        uint256 gasLimit,
        address rewardAddress,
        bytes32 blockDataHash
    );

    event SequencerSet(address indexed sequencer, bool indexed permissioned);

    function setUp() public virtual {
        target = HOST_ZENITH;

        // configure a local signer as a sequencer
        vm.prank(SEQUENCER_ADMIN);
        target.addSequencer(vm.addr(sequencerKey));
    }

    // cannot submit block with incorrect host block number
    function test_incorrectHostBlock(Zenith.BlockHeader memory header, bytes memory blockData) public {
        vm.assume(header.hostBlockNumber != block.number);

        // sign block commitment with sequencer key
        bytes32 commit = target.blockCommitment(header);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sequencerKey, commit);

        vm.expectRevert(Zenith.IncorrectHostBlock.selector);
        target.submitBlock(header, v, r, s, blockData);
    }

    // can submit block successfully with acceptable header & correct signature provided
    function test_submitBlock(Zenith.BlockHeader memory header, bytes memory blockData) public {
        vm.assume(header.hostBlockNumber == block.number);

        // sign block commitment with correct sequencer key
        bytes32 commit = target.blockCommitment(header);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sequencerKey, commit);

        assertNotEq(target.lastSubmittedAtBlock(header.rollupChainId), block.number);

        // should emit BlockSubmitted event
        vm.expectEmit();
        emit BlockSubmitted(
            vm.addr(sequencerKey), header.rollupChainId, header.gasLimit, header.rewardAddress, header.blockDataHash
        );
        target.submitBlock(header, v, r, s, blockData);

        assertEq(target.lastSubmittedAtBlock(header.rollupChainId), block.number);
    }

    // cannot submit block with invalid sequencer signer from non-permissioned key
    function test_notSequencer(uint256 notSequencerKey, Zenith.BlockHeader memory header, bytes memory blockData)
        public
    {
        vm.assume(notSequencerKey != sequencerKey);
        vm.assume(
            notSequencerKey != 0
                && notSequencerKey < 115792089237316195423570985008687907852837564279074904382605163141518161494337
        );
        vm.assume(header.hostBlockNumber == block.number);

        // sign block commitment with NOT sequencer key
        bytes32 commit = target.blockCommitment(header);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(notSequencerKey, commit);

        vm.expectRevert(abi.encodeWithSelector(Zenith.BadSignature.selector, vm.addr(notSequencerKey)));
        target.submitBlock(header, v, r, s, blockData);
    }

    // cannot submit block with sequencer signature over different block header data
    function test_badSignature(
        Zenith.BlockHeader memory header1,
        Zenith.BlockHeader memory header2,
        bytes memory blockData
    ) public {
        // assume the two headers are different in some way
        vm.assume(
            header1.rollupChainId != header2.rollupChainId || header1.hostBlockNumber != header2.hostBlockNumber
                || header1.gasLimit != header2.gasLimit || header1.rewardAddress != header2.rewardAddress
                || header1.blockDataHash != header2.blockDataHash
        );
        vm.assume(header2.hostBlockNumber == block.number);

        // sign original block commitment with sequencer key
        bytes32 commit1 = target.blockCommitment(header1);
        bytes32 commit2 = target.blockCommitment(header2);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sequencerKey, commit1);

        address derivedSigner = ecrecover(commit2, v, r, s);
        vm.expectRevert(abi.encodeWithSelector(Zenith.BadSignature.selector, derivedSigner));
        target.submitBlock(header2, v, r, s, blockData);
    }

    function test_addSequencer(uint256 notSequencerKey, Zenith.BlockHeader memory header, bytes memory blockData)
        public
    {
        vm.assume(notSequencerKey != sequencerKey);
        vm.assume(
            notSequencerKey != 0
                && notSequencerKey < 115792089237316195423570985008687907852837564279074904382605163141518161494337
        );
        vm.assume(header.hostBlockNumber == block.number);

        address newSequencer = vm.addr(notSequencerKey);
        assertFalse(target.isSequencer(newSequencer));

        vm.startPrank(SEQUENCER_ADMIN);
        vm.expectEmit();
        emit SequencerSet(newSequencer, true);
        target.addSequencer(newSequencer);
        vm.stopPrank();

        assertTrue(target.isSequencer(newSequencer));

        // can sign block now with new sequencer key
        bytes32 commit = target.blockCommitment(header);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(notSequencerKey, commit);
        vm.expectEmit();
        emit BlockSubmitted(
            newSequencer, header.rollupChainId, header.gasLimit, header.rewardAddress, header.blockDataHash
        );
        target.submitBlock(header, v, r, s, blockData);
    }

    function test_notSequencerAdmin(address caller, address sequencer) public {
        vm.assume(caller != SEQUENCER_ADMIN);
        vm.startPrank(caller);

        vm.expectRevert(Zenith.OnlySequencerAdmin.selector);
        target.addSequencer(sequencer);

        vm.expectRevert(Zenith.OnlySequencerAdmin.selector);
        target.removeSequencer(sequencer);
    }
}
