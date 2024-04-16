// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// import openzeppelin Role contracts
import {HostPassage} from "./Passage.sol";
import {AccessControlDefaultAdminRules} from
    "openzeppelin-contracts/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

contract Zenith is HostPassage, AccessControlDefaultAdminRules {
    struct BlockHeader {
        uint256 rollupChainId;
        uint256 sequence;
        uint256 gasLimit;
        uint256 confirmBy;
        address rewardAddress;
    }

    /// @notice Role that allows an address to sign commitments to rollup blocks.
    bytes32 public constant SEQUENCER_ROLE = bytes32("SEQUENCER_ROLE");

    /// @notice The sequence number of the next block that can be submitted.
    /// rollupChainId => nextSequence number
    mapping(uint256 => uint256) public nextSequence;

    /// @notice Thrown when a block submission is attempted with a sequence number that is not the next block.
    /// @dev Blocks must be submitted in strict increasing order.
    /// @param expected - the correct next sequence number for the given rollup chainId.
    error BadSequence(uint256 expected);

    /// @notice Thrown when a block submission is attempted where confirmBy time has passed.
    error BlockExpired();

    /// @notice Thrown when a block submission is attempted with a signature over malformed data.
    /// @param hashes - the encoded blob hashes attached to the transaction.
    ///                 this is the most useful data to debug a bad signature off-chain.
    /// @param v - the v component of the Sequencer's ECSDA signature over the block commitment.
    /// @param r - the r component of the Sequencer's ECSDA signature over the block commitment.
    /// @param s - the s component of the Sequencer's ECSDA signature over the block commitment.
    error BadSignature(bytes hashes, uint8 v, bytes32 r, bytes32 s);

    /// @notice Thrown when a block submission is attempted signed by a non-permissioned sequencer.
    /// @param sequencer - the signer of the block data that is not a permissioned sequencer.
    error NotSequencer(address sequencer);

    /// @notice Emitted when a new rollup block is successfully submitted.
    /// @param sequencer - the address of the sequencer that signed the block.
    /// @param header - the block header information for the block.
    /// @param blobIndices - the indices of the 4844 blob hashes for the block data.
    event BlockSubmitted(address indexed sequencer, BlockHeader indexed header, uint32[] blobIndices);

    /// @notice Initializes the Admin role.
    /// @dev See `AccessControlDefaultAdminRules` for information on contract administration.
    ///      - Admin role can grant and revoke Sequencer roles.
    ///      - Admin role can be transferred via two-step process with a 1 day timelock.
    /// @param admin - the address that will be the initial admin.
    constructor(address admin) AccessControlDefaultAdminRules(1 days, admin) {}

    /// @notice Submit a rollup block with block data stored in 4844 blobs.
    /// @dev Blocks are submitted by Builders, with an attestation to the block data signed by a Sequencer.
    /// @param header - the header information for the rollup block.
    /// @param blobIndices - the indices of the 4844 blob hashes for the block data.
    /// @param v - the v component of the Sequencer's ECSDA signature over the block commitment.
    /// @param r - the r component of the Sequencer's ECSDA signature over the block commitment.
    /// @param s - the s component of the Sequencer's ECSDA signature over the block commitment.
    /// @custom:reverts BadSequence if the sequence number is not the next block for the given rollup chainId.
    /// @custom:reverts BlockExpired if the confirmBy time has passed.
    /// @custom:reverts BadSignature if the signature provided commits to different block data.
    /// @custom:reverts NotSequencer if the signer is not a permissioned sequencer.
    /// @custom:emits BlockSubmitted if the block is successfully submitted.
    function submitBlock(BlockHeader memory header, uint32[] memory blobIndices, uint8 v, bytes32 r, bytes32 s)
        external
    {
        // assert that the sequence number is valid and increment it
        uint256 _nextSequence = nextSequence[header.rollupChainId]++;
        if (_nextSequence != header.sequence) revert BadSequence(_nextSequence);

        // assert that confirmBy time has not passed
        if (block.timestamp > header.confirmBy) revert BlockExpired();

        // derive block commitment from sequence number and blobhashes
        (bytes32 blockCommit, bytes memory hashes) = blockCommitment(header, blobIndices);

        // derive sequencer from signature
        address sequencer = ecrecover(blockCommit, v, r, s);

        // if the derived signer is address(0), the signature is invalid over the derived blockCommit
        // emit the data required to inspect the signature off-chain
        if (sequencer == address(0)) revert BadSignature(hashes, v, r, s);

        // assert that sequencer is permissioned
        if (!hasRole(SEQUENCER_ROLE, sequencer)) revert NotSequencer(sequencer);

        // emit event
        emit BlockSubmitted(sequencer, header, blobIndices);
    }

    /// @notice Construct hash of block details that the sequencer signs.
    /// @dev See `getCommit` for hash data encoding.
    /// @dev Used to easily generate a correct commit hash off-chain for the sequencer to sign.
    /// @param header - the header information for the rollup block.
    /// @param blobHashes - the 4844 blob hashes for the block data.
    /// @param commit - the hash of the encoded block details.
    function blockCommitment(BlockHeader memory header, bytes32[] memory blobHashes)
        external
        view
        returns (bytes32 commit)
    {
        commit = getCommit(header, packHashes(blobHashes));
    }

    /// @notice Encode the array of blob hashes into a bytes string.
    /// @param blobHashes - the 4844 blob hashes for the block data.
    /// @return encodedHashes - the encoded blob hashes.
    function packHashes(bytes32[] memory blobHashes) public pure returns (bytes memory encodedHashes) {
        for (uint32 i = 0; i < blobHashes.length; i++) {
            encodedHashes = abi.encodePacked(encodedHashes, blobHashes[i]);
        }
    }

    /// @notice Construct hash of block details that the sequencer signs.
    /// @dev See `getCommit` for hash data encoding.
    /// @dev Used within the transaction in which the block data is submitted as a 4844 blob.
    ///      Relies on blob indices, which are used to read blob hashes from the transaction.
    /// @param header - the header information for the rollup block.
    /// @param blobIndices - the indices of the 4844 blob hashes for the block data.
    /// @param commit - the hash of the encoded block details.
    function blockCommitment(BlockHeader memory header, uint32[] memory blobIndices)
        internal
        view
        returns (bytes32 commit, bytes memory hashes)
    {
        hashes = getHashes(blobIndices);
        commit = getCommit(header, hashes);
    }

    /// @notice Encode an array of blob hashes, given their indices in the transaction.
    /// @param blobIndices - the indices of the 4844 blob hashes for the block data.
    /// @return encodedHashes - the encoded blob hashes.
    function getHashes(uint32[] memory blobIndices) internal view returns (bytes memory encodedHashes) {
        for (uint32 i = 0; i < blobIndices.length; i++) {
            encodedHashes = abi.encodePacked(encodedHashes, blobhash(blobIndices[i]));
        }
    }

    /// @notice Construct hash of block details that the sequencer signs.
    /// @dev Hash is keccak256(abi.encodePacked("init4.sequencer.v0", hostChainId, rollupChainId, blockSequence, rollupGasLimit, confirmBy, rewardAddress, numBlobs, encodedBlobHashes))
    /// @param header - the header information for the rollup block.
    /// @param encodedHashes - the encoded blob hashes.
    /// @return commit - the hash of the encoded block details.
    function getCommit(BlockHeader memory header, bytes memory encodedHashes) internal view returns (bytes32 commit) {
        bytes memory encoded = abi.encodePacked(
            "init4.sequencer.v0",
            block.chainid,
            header.rollupChainId,
            header.sequence,
            header.gasLimit,
            header.confirmBy,
            header.rewardAddress,
            encodedHashes.length / 32,
            encodedHashes
        );
        commit = keccak256(encoded);
    }
}
