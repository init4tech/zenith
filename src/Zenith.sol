// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// import openzeppelin Role contracts
import {Passage} from "./Passage.sol";
import {AccessControlDefaultAdminRules} from
    "openzeppelin-contracts/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

contract Zenith is Passage, AccessControlDefaultAdminRules {
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

    /// @notice The host block number that a block was last submitted at for a given rollup chainId.
    /// rollupChainId => host blockNumber that block was last submitted at
    mapping(uint256 => uint256) public lastSubmittedAtBlock;

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

    /// @notice Thrown when attempting to submit more than one rollup block per host block
    error OneRollupBlockPerHostBlock();

    /// @notice Emitted when a new rollup block is successfully submitted.
    /// @param sequencer - the address of the sequencer that signed the block.
    /// @param header - the block header information for the block.
    /// @param blockDataHash - keccak256(blockData). the Node will discard the block if the hash doens't match.
    event BlockSubmitted(address indexed sequencer, BlockHeader indexed header, bytes32 blockDataHash);

    /// @notice Emit the entire block data for easy visibility
    event BlockData(bytes blockData);

    /// @notice Initializes the Admin role.
    /// @dev See `AccessControlDefaultAdminRules` for information on contract administration.
    ///      - Admin role can grant and revoke Sequencer roles.
    ///      - Admin role can be transferred via two-step process with a 1 day timelock.
    /// @param admin - the address that will be the initial admin.
    constructor(uint256 defaultRollupChainId, address admin)
        Passage(defaultRollupChainId)
        AccessControlDefaultAdminRules(1 days, admin)
    {}

    /// @notice Submit a rollup block with block data submitted via calldata.
    /// @dev Blocks are submitted by Builders, with an attestation to the block data signed by a Sequencer.
    /// @param header - the header information for the rollup block.
    /// @param blockDataHash - keccak256(blockData). the Node will discard the block if the hash doens't match.
    /// @dev including blockDataHash allows the sequencer to sign over finalized block data, without needing to calldatacopy the `blockData` param.
    /// @param v - the v component of the Sequencer's ECSDA signature over the block header.
    /// @param r - the r component of the Sequencer's ECSDA signature over the block header.
    /// @param s - the s component of the Sequencer's ECSDA signature over the block header.
    /// @param blockData - block data information. could be packed blob hashes, or direct rlp-encoded transctions. blockData is ignored by the contract logic.
    /// @custom:reverts BadSequence if the sequence number is not the next block for the given rollup chainId.
    /// @custom:reverts BlockExpired if the confirmBy time has passed.
    /// @custom:reverts BadSignature if the signer is not a permissioned sequencer,
    ///                 OR if the signature provided commits to a different header.
    /// @custom:reverts OneRollupBlockPerHostBlock if attempting to submit a second rollup block within one host block.
    /// @custom:emits BlockSubmitted if the block is successfully submitted.
    /// @custom:emits BlockData to expose the block calldata; as a convenience until calldata tracing is implemented in the Node.
    function submitBlock(
        BlockHeader memory header,
        bytes32 blockDataHash,
        uint8 v,
        bytes32 r,
        bytes32 s,
        bytes calldata blockData
    ) external {
        _submitBlock(header, blockDataHash, v, r, s);
        emit BlockData(blockData);
    }

    function _submitBlock(BlockHeader memory header, bytes32 blockDataHash, uint8 v, bytes32 r, bytes32 s) internal {
        // assert that the sequence number is valid and increment it
        uint256 _nextSequence = nextSequence[header.rollupChainId]++;
        if (_nextSequence != header.sequence) revert BadSequence(_nextSequence);

        // assert that confirmBy time has not passed
        if (block.timestamp > header.confirmBy) revert BlockExpired();

        // derive sequencer from signature over block header
        bytes32 blockCommit = blockCommitment(header, blockDataHash);
        address sequencer = ecrecover(blockCommit, v, r, s);

        // assert that signature is valid && sequencer is permissioned
        if (!hasRole(SEQUENCER_ROLE, sequencer)) revert BadSignature(sequencer);

        // assert this is the first rollup block submitted for this host block
        if (lastSubmittedAtBlock[header.rollupChainId] == block.number) revert OneRollupBlockPerHostBlock();
        lastSubmittedAtBlock[header.rollupChainId] = block.number;

        // emit event
        emit BlockSubmitted(sequencer, header, blockDataHash);
    }

    /// @notice Construct hash of block details that the sequencer signs.
    /// @param header - the header information for the rollup block.
    /// @return commit - the hash of the encoded block details.
    function blockCommitment(BlockHeader memory header, bytes32 blockDataHash) public view returns (bytes32 commit) {
        bytes memory encoded = abi.encodePacked(
            "init4.sequencer.v0",
            block.chainid,
            header.rollupChainId,
            header.sequence,
            header.gasLimit,
            header.confirmBy,
            header.rewardAddress,
            blockDataHash
        );
        commit = keccak256(encoded);
    }
}
