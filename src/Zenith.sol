// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// import openzeppelin Role contracts
import {HostPassage} from "./Passage.sol";
import {AccessControlDefaultAdminRules} from
    "openzeppelin-contracts/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

contract Zenith is HostPassage, AccessControlDefaultAdminRules {
    // @notice Role that allows an address to sign commitments to rollup blocks.
    bytes32 public constant SEQUENCER_ROLE = bytes32("SEQUENCER_ROLE");

    // @notice The sequence number of the next block that can be submitted.
    uint256 public nextSequence;

    // @notice Thrown when a block submission is attempted with a sequence number that is not the next block.
    // @dev Blocks must be submitted in strict increasing order.
    // @param expected - the sequence number of the next block that can be submitted.
    // @param actual - the sequence number of the block that was submitted.
    error BadSequence(uint256 expected, uint256 actual);

    // @notice Thrown when a block submission is attempted with a bad signature.
    // @dev Can indicate that the commit signer is not a permissioned sequencer, OR
    //      that the signed data was malformed or invalid.
    // @param signer - the signer derived from the commit hash & signature.
    //                 If this is an unexpected value, the commit data might be malformed or invalid.
    // @param commit - the commit hash derived from the block data.
    //                 If this value is expected, the signer was not a sequencer permissioned with the SEQUENCER_ROLE.
    error BadSignature(address signer, bytes32 commit);

    // @notice Emitted when a new rollup block is successfully submitted.
    // @param sequence - the sequence number of the block.
    // @param sequencer - the address of the sequencer that signed the block.
    // @param blobIndices - the indices of the 4844 blob hashes for the block data.
    // TODO: can an off-chain observer easily get the blob data from the transaction using the blob indices?
    event BlockSubmitted(uint256 indexed sequence, address indexed sequencer, uint32[] blobIndices);

    // @notice Sets the deployer as the Admin role.
    // @dev See `AccessControlDefaultAdminRules` for information on contract administration.
    //      - Admin role can grant and revoke Sequencer roles.
    //      - Admin role can be transferred via two-step process with a 1 day timelock.
    constructor() AccessControlDefaultAdminRules(1 days, msg.sender) {}

    // @notice Submit a rollup block with block data stored in 4844 blobs.
    // @dev Blocks are submitted by Builders, with an attestation to the block data signed by a Sequencer.
    // @param blockSequence - the sequence number of the block.
    // @param blobIndices - the indices of the 4844 blob hashes for the block data.
    // @param v - the v component of the Sequencer's ECSDA signature over the block commitment.
    // @param r - the r component of the Sequencer's ECSDA signature over the block commitment.
    // @param s - the s component of the Sequencer's ECSDA signature over the block commitment.
    // @custom:reverts BadSequence if the sequence number is not the next block.
    // @custom:reverts BadSignature if the signature provided commits to different block data,
    //                 OR if the signer is not a permissioned sequencer.
    // @custom:emits BlockSubmitted if the block is successfully submitted.
    function submitBlock(uint256 blockSequence, uint32[] memory blobIndices, uint8 v, bytes32 r, bytes32 s) external {
        // assert that the sequence number is valid and increment it
        uint256 _nextSequence = nextSequence++;
        if (_nextSequence != blockSequence) revert BadSequence(_nextSequence, blockSequence);

        // derive block commitment from sequence number and blobhashes
        bytes32 blockCommit = blockCommitment(blockSequence, blobIndices);

        // derive sequencer from signature
        address sequencer = ecrecover(blockCommit, v, r, s);

        // assert that sequencer is permissioned
        if (!hasRole(SEQUENCER_ROLE, sequencer)) revert BadSignature(sequencer, blockCommit);

        // emit event
        emit BlockSubmitted(blockSequence, sequencer, blobIndices);
    }

    // @notice Construct hash of block details that the sequencer signs.
    // @dev See `getCommit` for hash data encoding.
    // @dev Used to easily generate a correct commit hash off-chain for the sequencer to sign.
    // @param blockSequence - the sequence number of the block.
    // @param blobHashes - the 4844 blob hashes for the block data.
    // @param commit - the hash of the encoded block details.
    function blockCommitment(uint256 blockSequence, bytes32[] memory blobHashes)
        external
        view
        returns (bytes32 commit)
    {
        commit = getCommit(blockSequence, packHashes(blobHashes));
    }

    // @notice Construct hash of block details that the sequencer signs.
    // @dev See `getCommit` for hash data encoding.
    // @dev Used within the transaction in which the block data is submitted as a 4844 blob.
    //      Relies on blob indices, which are used to read blob hashes from the transaction.
    // @param blockSequence - the sequence number of the block.
    // @param blobIndices - the indices of the 4844 blob hashes for the block data.
    // @param commit - the hash of the encoded block details.
    function blockCommitment(uint256 blockSequence, uint32[] memory blobIndices)
        internal
        view
        returns (bytes32 commit)
    {
        commit = getCommit(blockSequence, getHashes(blobIndices));
    }

    // @notice Encode the array of blob hashes into a bytes string.
    // @param blobHashes - the 4844 blob hashes for the block data.
    // @return encodedHashes - the encoded blob hashes.
    function packHashes(bytes32[] memory blobHashes) internal pure returns (bytes memory encodedHashes) {
        for (uint32 i = 0; i < blobHashes.length; i++) {
            encodedHashes = abi.encodePacked(encodedHashes, blobHashes[i]);
        }
    }

    // @notice Encode an array of blob hashes, given their indices in the transaction.
    // @param blobIndices - the indices of the 4844 blob hashes for the block data.
    // @return encodedHashes - the encoded blob hashes.
    function getHashes(uint32[] memory blobIndices) internal view returns (bytes memory encodedHashes) {
        for (uint32 i = 0; i < blobIndices.length; i++) {
            encodedHashes = abi.encodePacked(encodedHashes, blobhash(blobIndices[i]));
        }
    }

    // @notice Construct hash of block details that the sequencer signs.
    // @dev Hash is keccak256(abi.encodePacked("zenith", hostChainId, blockSequence, encodedBlobHashesLength, encodedBlobHashes))
    // @param blockSequence - the sequence number of the block.
    // @param encodedHashes - the encoded blob hashes.
    // @return commit - the hash of the encoded block details.
    function getCommit(uint256 blockSequence, bytes memory encodedHashes) internal view returns (bytes32 commit) {
        bytes memory encoded =
            abi.encodePacked("zenith", block.chainid, blockSequence, encodedHashes.length, encodedHashes);
        commit = keccak256(encoded);
    }
}
