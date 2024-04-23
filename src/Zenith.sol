// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// import openzeppelin Role contracts
import {HostPassage} from "./Passage.sol";
import {AccessControlDefaultAdminRules} from
    "openzeppelin-contracts/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

contract Zenith is HostPassage, AccessControlDefaultAdminRules {
    /// @notice The location where the block data was submitted.
    /// @param Blobs - the block data was submitted as 4844 blobs. the `submitBlock` calldata contains `blobIndices` which can be used to pull the blobs / blob hashes.
    /// @param Calldata - the block data was submitted directly via the `submitBlock` calldata.
    enum DataLocation {
        Blobs,
        Calldata
    }
    /// @notice Block header information for the rollup block, signed by the sequencer.
    /// @param rollupChainId - the chainId of the rollup chain. Any chainId is accepted by the contract.
    /// @param sequence - the sequence number of the rollup block. Must be monotonically increasing. Enforced by the contract.
    /// @param confirmBy - the timestamp by which the block must be submitted. Enforced by the contract.
    /// @param gasLimit - the gas limit for the rollup block. Ignored by the contract; enforced by the Node.
    /// @param rewardAddress - the address to receive the rollup block reward. Ignored by the contract; enforced by the Node.

    struct BlockHeader {
        uint256 rollupChainId;
        uint256 sequence;
        uint256 confirmBy;
        uint256 gasLimit;
        address rewardAddress;
    }

    /// @notice Role that allows a key to sign commitments to rollup blocks.
    bytes32 public constant SEQUENCER_ROLE = bytes32("SEQUENCER_ROLE");

    /// @notice The sequence number of the next block that can be submitted for a given rollup chainId.
    /// rollupChainId => nextSequence number
    mapping(uint256 => uint256) public nextSequence;

    /// @notice Thrown when a block submission is attempted with a sequence number that is not the next block for the rollup chainId.
    /// @dev Blocks must be submitted in strict monotonic increasing order.
    /// @param expected - the correct next sequence number for the given rollup chainId.
    error BadSequence(uint256 expected);

    /// @notice Thrown when a block submission is attempted when the confirmBy time has passed.
    error BlockExpired();

    /// @notice Thrown when a block submission is attempted with a signature by a non-permissioned sequencer,
    ///         OR when signature is produced over different data than is provided.
    /// @param derivedSequencer - the derived signer of the block data that is not a permissioned sequencer.
    error BadSignature(address derivedSequencer);

    /// @notice Emitted when a new rollup block is successfully submitted.
    /// @param location - the location where the block data was submitted.
    /// @param sequencer - the address of the sequencer that signed the block.
    /// @param header - the block header information for the block.
    event BlockSubmitted(DataLocation indexed location, address indexed sequencer, BlockHeader indexed header);

    /// @notice Emit the entire block data for easy visibility
    event BlockData(bytes blockData);

    /// @notice Emit the blob indices for easy visibility
    event BlobIndices(uint32[] blobIndices);

    /// @notice Initializes the Admin role.
    /// @dev See `AccessControlDefaultAdminRules` for information on contract administration.
    ///      - Admin role can grant and revoke Sequencer roles.
    ///      - Admin role can be transferred via two-step process with a 1 day timelock.
    /// @param admin - the address that will be the initial admin.
    constructor(address admin) AccessControlDefaultAdminRules(1 days, admin) {}

    /// @notice Submit a rollup block with block data submitted via calldata.
    /// @param header - see _submitBlock.
    /// @param blockData - full data for the block supplied directly.
    /// @param v - see _submitBlock.
    /// @param r - see _submitBlock.
    /// @param s - see _submitBlock.
    /// @custom:reverts see _submitBlock.
    /// @custom:emits see _submitBlock.
    function submitBlock(BlockHeader memory header, bytes calldata blockData, uint8 v, bytes32 r, bytes32 s) external {
        bytes32 blockCommit = blockCommitment(header, blockData);

        _submitBlock(DataLocation.Calldata, header, blockCommit, v, r, s);

        emit BlockData(blockData);
    }

    /// @notice Submit a rollup block with block data stored in 4844 blobs.
    /// @param header - see _submitBlock.
    /// @param blobIndices - the indices of the 4844 blob hashes for the block data.
    /// @param v - see _submitBlock.
    /// @param r - see _submitBlock.
    /// @param s - see _submitBlock.
    /// @custom:reverts see _submitBlock.
    /// @custom:emits see _submitBlock.
    function submitBlock(BlockHeader memory header, uint32[] calldata blobIndices, uint8 v, bytes32 r, bytes32 s)
        external
    {
        bytes32 blockCommit = blockCommitment(header, blobIndices);

        _submitBlock(DataLocation.Blobs, header, blockCommit, v, r, s);

        emit BlobIndices(blobIndices);
    }

    /// @notice Submit a rollup block.
    /// @dev Blocks are submitted by Builders, with an attestation to the block data signed by a Sequencer.
    /// @param header - the header information for the rollup block.
    /// @param blockCommit - the hashes `blockCommitment` signed by the Sequencer.
    /// @param v - the v component of the Sequencer's ECSDA signature over the block commitment.
    /// @param r - the r component of the Sequencer's ECSDA signature over the block commitment.
    /// @param s - the s component of the Sequencer's ECSDA signature over the block commitment.
    /// @custom:reverts BadSequence if the sequence number is not the next block for the given rollup chainId.
    /// @custom:reverts BlockExpired if the confirmBy time has passed.
    /// @custom:reverts BadSignature if the signer is not a permissioned sequencer,
    ///                 OR if the signature provided commits to different block data.
    /// @custom:emits BlockSubmitted if the block is successfully submitted.
    function _submitBlock(
        DataLocation location,
        BlockHeader memory header,
        bytes32 blockCommit,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        // assert that the sequence number is valid and increment it
        uint256 _nextSequence = nextSequence[header.rollupChainId]++;
        if (_nextSequence != header.sequence) revert BadSequence(_nextSequence);

        // assert that confirmBy time has not passed
        if (block.timestamp > header.confirmBy) revert BlockExpired();

        // derive sequencer from signature
        address sequencer = ecrecover(blockCommit, v, r, s);

        // assert that signature is valid && sequencer is permissioned
        if (!hasRole(SEQUENCER_ROLE, sequencer)) revert BadSignature(sequencer);

        // emit event
        emit BlockSubmitted(location, sequencer, header);
    }

    /// @notice Encode an array of blob hashes, given their indices in the transaction.
    /// @param blobIndices - the indices of the 4844 blob hashes for the block data.
    /// @return encodedHashes - the encoded blob hashes.
    function getHashes(uint32[] calldata blobIndices) internal view returns (bytes memory encodedHashes) {
        for (uint32 i = 0; i < blobIndices.length; i++) {
            encodedHashes = abi.encodePacked(encodedHashes, blobhash(blobIndices[i]));
        }
    }

    /// @notice Construct hash of block details that the sequencer signs.
    /// @dev NOTE: we have separate blockCommitment functions in order to keep `blockData` as `calldata`, which is not possible for `encodedHashes`
    /// @param header - the header information for the rollup block.
    /// @param blockData - full data for the block supplied directly.
    /// @return commit - the hash of the encoded block details.
    function blockCommitment(BlockHeader memory header, bytes calldata blockData)
        public
        view
        returns (bytes32 commit)
    {
        bytes memory encoded = abi.encodePacked(
            "init4.sequencer.v0",
            block.chainid,
            header.rollupChainId,
            header.sequence,
            header.gasLimit,
            header.confirmBy,
            header.rewardAddress,
            blockData.length,
            blockData
        );
        commit = keccak256(encoded);
    }

    /// @notice Construct hash of block details that the sequencer signs.
    /// @param header - the header information for the rollup block.
    /// @param blobIndices - the indices of the 4844 blob hashes for the block data.
    /// @return commit - the hash of the encoded block details.
    function blockCommitment(BlockHeader memory header, uint32[] calldata blobIndices)
        public
        view
        returns (bytes32 commit)
    {
        // query the blob hashes via the indices in order to
        // ensure that the committed blob hashes are available in the transaction.
        bytes memory encodedHashes = getHashes(blobIndices);

        bytes memory encoded = abi.encodePacked(
            "init4.sequencer.v0",
            block.chainid,
            header.rollupChainId,
            header.sequence,
            header.gasLimit,
            header.confirmBy,
            header.rewardAddress,
            encodedHashes.length,
            encodedHashes
        );
        commit = keccak256(encoded);
    }
}
