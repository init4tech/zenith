// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Passage} from "./Passage.sol";

contract Zenith is Passage {
    /// @notice The address that is allowed to set/remove sequencers.
    address public immutable sequencerAdmin;
    /// @notice The block number at which the Zenith contract was deployed.
    uint256 public immutable deployBlockNumber;

    /// @notice Block header information for the rollup block, signed by the sequencer.
    /// @param rollupChainId - the chainId of the rollup chain. Any chainId is accepted by the contract.
    /// @param hostBlockNumber - the host block number in which the rollup block must be submitted. Enforced by the contract.
    /// @param gasLimit - the gas limit for the rollup block. Ignored by the contract; enforced by the Node.
    /// @param rewardAddress - the address to receive the rollup block reward. Ignored by the contract; enforced by the Node.
    /// @param blockDataHash - keccak256(rlp-encoded transactions). the Node will discard the block if the hash doens't match.
    ///                        this allows the sequencer to sign over finalized set of transactions,
    ///                        without the Zenith contract needing to interact with raw transaction data (which may be provided via blobs or calldata).
    struct BlockHeader {
        uint256 rollupChainId;
        uint256 hostBlockNumber;
        uint256 gasLimit;
        address rewardAddress;
        bytes32 blockDataHash;
    }

    /// @notice The host block number that a block was last submitted at for a given rollup chainId.
    /// rollupChainId => host blockNumber that block was last submitted at
    mapping(uint256 => uint256) public lastSubmittedAtBlock;

    /// @notice Registry of permissioned sequencers.
    /// address => TRUE if it's a permissioned sequencer
    mapping(address => bool) public isSequencer;

    /// @notice Thrown when a block submission is attempted in the incorrect host block.
    error IncorrectHostBlock();

    /// @notice Thrown when a block submission is attempted with a signature by a non-permissioned sequencer,
    ///         OR when signature is produced over different block header than is provided.
    /// @param derivedSequencer - the derived signer of the block header that is not a permissioned sequencer.
    error BadSignature(address derivedSequencer);

    /// @notice Thrown when attempting to submit more than one rollup block per host block
    error OneRollupBlockPerHostBlock();

    /// @notice Thrown when attempting to modify sequencer roles if not sequencerAdmin.
    error OnlySequencerAdmin();

    /// @notice Emitted when a new rollup block is successfully submitted.
    /// @param sequencer - the address of the sequencer that signed the block.
    /// @param rollupChainId - the chainId of the rollup chain.
    /// @param gasLimit - the gas limit for the rollup block.
    /// @param rewardAddress - the address to receive the rollup block reward.
    /// @param blockDataHash - keccak256(rlp-encoded transactions). the Node will discard the block if the hash doens't match transactions provided.
    /// @dev including blockDataHash allows the sequencer to sign over finalized block data, without needing to calldatacopy the `blockData` param.
    event BlockSubmitted(
        address indexed sequencer,
        uint256 indexed rollupChainId,
        uint256 gasLimit,
        address rewardAddress,
        bytes32 blockDataHash
    );

    /// @notice Emitted when a sequencer is added or removed.
    event SequencerSet(address indexed sequencer, bool indexed permissioned);

    constructor(uint256 _defaultRollupChainId, address _withdrawalAdmin, address _sequencerAdmin)
        Passage(_defaultRollupChainId, _withdrawalAdmin)
    {
        sequencerAdmin = _sequencerAdmin;
        deployBlockNumber = block.number;
    }

    /// @notice Add a sequencer to the permissioned sequencer list.
    /// @param sequencer - the address of the sequencer to add.
    /// @custom:emits SequencerSet if the sequencer is added.
    /// @custom:reverts OnlySequencerAdmin if the caller is not the sequencerAdmin.
    function addSequencer(address sequencer) external {
        if (msg.sender != sequencerAdmin) revert OnlySequencerAdmin();
        if (isSequencer[sequencer]) return;
        isSequencer[sequencer] = true;
        emit SequencerSet(sequencer, true);
    }

    /// @notice Remove a sequencer from the permissioned sequencer list.
    /// @param sequencer - the address of the sequencer to remove.
    /// @custom:emits SequencerSet if the sequencer is removed.
    /// @custom:reverts OnlySequencerAdmin if the caller is not the sequencerAdmin.
    function removeSequencer(address sequencer) external {
        if (msg.sender != sequencerAdmin) revert OnlySequencerAdmin();
        if (!isSequencer[sequencer]) return;
        delete isSequencer[sequencer];
        emit SequencerSet(sequencer, false);
    }

    /// @notice Submit a rollup block.
    /// @dev Blocks are submitted by Builders, with an attestation to the block signed by a Sequencer.
    /// @param header - the header information for the rollup block.
    /// @param v - the v component of the Sequencer's ECSDA signature over the block header.
    /// @param r - the r component of the Sequencer's ECSDA signature over the block header.
    /// @param s - the s component of the Sequencer's ECSDA signature over the block header.
    /// @custom:reverts IncorrectHostBlock if the hostBlockNumber does not match the current block.
    /// @custom:reverts BadSignature if the signer is not a permissioned sequencer,
    ///                 OR if the signature provided commits to a different header.
    /// @custom:reverts OneRollupBlockPerHostBlock if attempting to submit a second rollup block within one host block.
    /// @custom:emits BlockSubmitted if the block is successfully submitted.
    function submitBlock(BlockHeader memory header, uint8 v, bytes32 r, bytes32 s, bytes calldata) external {
        // assert that the host block number matches the current block
        if (block.number != header.hostBlockNumber) revert IncorrectHostBlock();

        // derive sequencer from signature over block header
        bytes32 blockCommit = blockCommitment(header);
        address sequencer = ecrecover(blockCommit, v, r, s);

        // assert that signature is valid && sequencer is permissioned
        if (sequencer == address(0) || !isSequencer[sequencer]) revert BadSignature(sequencer);

        // assert this is the first rollup block submitted for this host block
        if (lastSubmittedAtBlock[header.rollupChainId] == block.number) revert OneRollupBlockPerHostBlock();
        lastSubmittedAtBlock[header.rollupChainId] = block.number;

        // emit event
        emit BlockSubmitted(
            sequencer, header.rollupChainId, header.gasLimit, header.rewardAddress, header.blockDataHash
        );
    }

    /// @notice Construct hash of block details that the sequencer signs.
    /// @param header - the header information for the rollup block.
    /// @return commit - the hash of the encoded block details.
    function blockCommitment(BlockHeader memory header) public view returns (bytes32 commit) {
        bytes memory encoded = abi.encodePacked(
            "init4.sequencer.v0",
            block.chainid,
            header.rollupChainId,
            header.hostBlockNumber,
            header.gasLimit,
            header.rewardAddress,
            header.blockDataHash
        );
        commit = keccak256(encoded);
    }
}
