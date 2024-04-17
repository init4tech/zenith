// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// import openzeppelin Role contracts
import {HostPassage} from "./Passage.sol";
import {AccessControlDefaultAdminRules} from
    "openzeppelin-contracts/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

contract CalldataZenith is HostPassage, AccessControlDefaultAdminRules {
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

    /// @notice Thrown when a block submission is attempted with a signature over different data.
    error BadSignature();

    /// @notice Thrown when a block submission is attempted with a signature by a non-permissioned sequencer.
    /// @param sequencer - the signer of the block data that is not a permissioned sequencer.
    error NotSequencer(address sequencer);

    /// @notice Emitted when a new rollup block is successfully submitted.
    /// @param sequencer - the address of the sequencer that signed the block.
    /// @param header - the block header information for the block.
    event BlockSubmitted(address indexed sequencer, BlockHeader indexed header, bytes blockData);

    /// @notice Initializes the Admin role.
    /// @dev See `AccessControlDefaultAdminRules` for information on contract administration.
    ///      - Admin role can grant and revoke Sequencer roles.
    ///      - Admin role can be transferred via two-step process with a 1 day timelock.
    /// @param admin - the address that will be the initial admin.
    constructor(address admin) AccessControlDefaultAdminRules(1 days, admin) {}

    /// @notice Submit a rollup block with block data stored in 4844 blobs.
    /// @dev Blocks are submitted by Builders, with an attestation to the block data signed by a Sequencer.
    /// @param header - the header information for the rollup block.
    /// @param v - the v component of the Sequencer's ECSDA signature over the block commitment.
    /// @param r - the r component of the Sequencer's ECSDA signature over the block commitment.
    /// @param s - the s component of the Sequencer's ECSDA signature over the block commitment.
    /// @custom:reverts BadSequence if the sequence number is not the next block for the given rollup chainId.
    /// @custom:reverts BlockExpired if the confirmBy time has passed.
    /// @custom:reverts BadSignature if the signature provided commits to different block data.
    /// @custom:reverts NotSequencer if the signer is not a permissioned sequencer.
    /// @custom:emits BlockSubmitted if the block is successfully submitted.
    function submitBlock(BlockHeader memory header, bytes memory blockData, uint8 v, bytes32 r, bytes32 s)
        external
    {
        // assert that the sequence number is valid and increment it
        uint256 _nextSequence = nextSequence[header.rollupChainId]++;
        if (_nextSequence != header.sequence) revert BadSequence(_nextSequence);

        // assert that confirmBy time has not passed
        if (block.timestamp > header.confirmBy) revert BlockExpired();

        // derive block commitment from sequence number and blobhashes
        bytes32 blockCommit = blockCommitment(header, blockData);

        // derive sequencer from signature
        address sequencer = ecrecover(blockCommit, v, r, s);

        // if the derived signer is address(0), the signature is invalid over the derived blockCommit
        // emit the data required to inspect the signature off-chain
        if (sequencer == address(0)) revert BadSignature();

        // assert that sequencer is permissioned
        if (!hasRole(SEQUENCER_ROLE, sequencer)) revert NotSequencer(sequencer);

        // emit event
        emit BlockSubmitted(sequencer, header, blockData);
    }

    /// @notice Construct hash of the block data that the sequencer signs.
    /// @dev See `getCommit` for hashed data encoding.
    /// @dev Used to easily generate a correct commit hash off-chain for the sequencer to sign.
    /// @param header - the header information for the rollup block.
    /// @param commit - the hash of the encoded block details.
    function blockCommitment(BlockHeader memory header, bytes memory blockData)
        public
        view
        returns (bytes32 commit)
    {
        commit = getCommit(header, blockData);
    }

    /// @notice Construct hash of block details that the sequencer signs.
    /// @dev Hash is keccak256(abi.encodePacked("init4.sequencer.v0", hostChainId, rollupChainId, blockSequence, rollupGasLimit, confirmBy, rewardAddress, numBlobs, encodedBlobHashes))
    /// @param header - the header information for the rollup block.
    /// @return commit - the hash of the encoded block details.
    function getCommit(BlockHeader memory header, bytes memory blockData) internal view returns (bytes32 commit) {
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
}
