// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// import openzeppelin Role contracts
import "openzeppelin-contracts/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

contract Zenith is AccessControlDefaultAdminRules {
    bytes32 public constant SEQUENCER_ROLE = bytes32("SEQUENCER_ROLE");

    uint256 public nextSequence;

    // blocks must be submitted in strict increasing order 
    error BadSequence(uint256 expected, uint256 actual);

    // either the sequencer is not permissioned, or there's something wrong with the commit 
    // (e.g. blob indices submitted don't map to the committed blob hashes)
    // if the commit is wrong, the signer will be a junk value
    // if the sequencer is not permissioned, the signer & commit should be meaningful values, but the signer will not have the SEQUENCER_ROLE
    error BadSignature(address signer, bytes32 commit);

    // successful block submission
    event BlockSubmitted(uint256 indexed sequence, address indexed sequencer, uint32[] blobIndices);

    // set the deployer as the Admin role which can grant and revoke Sequencer roles
    // Admin role can be transferred via two-step initiate/accept process with a 1 day timelock
    constructor() AccessControlDefaultAdminRules(1 days, msg.sender) {}

    // ACCEPT BLOCKS
    // TODO: blobs must be in the correct order at the time that the sequencer signs the commitment. is that okay?
    function submitBlock(uint256 blockSequence, uint32[] memory blobIndices, uint8 v, bytes32 r, bytes32 s) external {
        // assert that the sequence number is valid and increment it
        uint256 _nextSequence = nextSequence++;
        if (blockSequence != _nextSequence) revert BadSequence(_nextSequence, blockSequence);

        // derive block commitment from sequence number and blobhashes 
        bytes32 commit = blockCommitment(blockSequence, blobIndices);
        
        // derive sequencer from signature
        address sequencer = ecrecover(commit, v, r, s);

        // assert that sequencer is permissioned
        if (!hasRole(SEQUENCER_ROLE, sequencer)) revert BadSignature(sequencer, commit);

        // emit event
        emit BlockSubmitted(blockSequence, sequencer, blobIndices);
    }

    function blockCommitment(uint256 blockSequence, bytes32[] memory blobHashes) external view returns(bytes32) {
        return _commit(blockSequence, _packHashes(blobHashes));
    }

    function _packHashes(bytes32[] memory blobHashes) internal pure returns (bytes memory hashes) {
        for(uint32 i = 0; i < blobHashes.length; i++) {
            hashes = abi.encodePacked(hashes, blobHashes[i]);
        }
    }

    function blockCommitment(uint256 blockSequence, uint32[] memory blobIndices) internal view returns(bytes32) {
        return _commit(blockSequence, _getHashes(blobIndices));
    }

    function _getHashes(uint32[] memory blobIndices) internal view returns(bytes memory hashes) {
        for (uint32 i = 0; i < blobIndices.length; i++) {
            hashes = abi.encodePacked(hashes, blobhash(blobIndices[i]));
        }
    }

    function _commit(uint256 blockSequence, bytes memory hashes) internal view returns(bytes32) {
        bytes memory commit = abi.encodePacked("zenith", block.chainid, blockSequence, hashes.length, hashes);
        return keccak256(commit);
    }
}
