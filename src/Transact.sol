// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.24;

import {Passage} from "./passage/Passage.sol";

/// @notice A contract deployed to Host chain that enables transactions from L1 to be sent on an L2.
contract Transactor {
    /// @notice The chainId of rollup that Ether will be sent to by default when entering the rollup via fallback() or receive().
    uint256 public immutable defaultRollupChainId;

    /// @notice The address that is allowed to configure `transact` gas limits.
    address public immutable gasAdmin;

    /// @notice The address of the Passage contract, to enable transact + enter.
    Passage public immutable passage;

    /// @notice The sum of `transact` calls in a block cannot use more than this limit.
    uint256 public perBlockGasLimit;

    /// @notice Each `transact` call cannot use more than this limit.
    uint256 public perTransactGasLimit;

    /// @notice The total gas used by `transact` so far in this block.
    /// rollupChainId => block number => `transasct` gasLimit used so far.
    mapping(uint256 => mapping(uint256 => uint256)) public transactGasUsed;

    /// @notice Emitted to send a special transaction to the rollup.
    event Transact(
        uint256 indexed rollupChainId,
        address indexed sender,
        address indexed to,
        bytes data,
        uint256 value,
        uint256 gas,
        uint256 maxFeePerGas
    );

    /// @notice Emitted when the admin configures gas limits.
    event GasConfigured(uint256 perBlock, uint256 perTransact);

    /// @notice Thrown when attempting to use more then the current global `transact` gasLimit for the block.
    error PerBlockTransactGasLimit();

    /// @notice Thrown when attempting to use too much gas per single `transact` call.
    error PerTransactGasLimit();

    /// @notice Thrown when attempting to configure gas if not the admin.
    error OnlyGasAdmin();

    /// @param _defaultRollupChainId - the chainId of the rollup that Ether will be sent to by default
    ///                                when entering the rollup via fallback() or receive() fns.
    constructor(
        uint256 _defaultRollupChainId,
        address _gasAdmin,
        Passage _passage,
        uint256 _perBlockGasLimit,
        uint256 _perTransactGasLimit
    ) {
        defaultRollupChainId = _defaultRollupChainId;
        gasAdmin = _gasAdmin;
        passage = _passage;
        _configureGas(_perBlockGasLimit, _perTransactGasLimit);
    }

    /// @notice Configure the `transact` gas limits.
    function configureGas(uint256 perBlock, uint256 perTransact) external {
        if (msg.sender != gasAdmin) revert OnlyGasAdmin();
        _configureGas(perBlock, perTransact);
    }

    /// @notice Allows a special transaction to be sent to the rollup with sender == L1 msg.sender.
    /// @dev Transaction is processed after normal rollup block execution.
    /// @dev See `enterTransact` for docs.
    function transact(
        uint256 rollupChainId,
        address to,
        bytes calldata data,
        uint256 value,
        uint256 gas,
        uint256 maxFeePerGas
    ) external payable {
        enterTransact(rollupChainId, msg.sender, to, data, value, gas, maxFeePerGas);
    }

    /// @dev See `transact` for docs.
    function transact(address to, bytes calldata data, uint256 value, uint256 gas, uint256 maxFeePerGas)
        external
        payable
    {
        enterTransact(defaultRollupChainId, msg.sender, to, data, value, gas, maxFeePerGas);
    }

    /// @notice Send Ether on the rollup, send a special transaction to be sent to the rollup with sender == L1 msg.sender.
    /// @dev Enter and Transact are processed after normal rollup block execution.
    /// @dev See `enter` for Enter docs.
    /// @param rollupChainId - The rollup chain to send the transaction to.
    /// @param etherRecipient - The recipient of the ether.
    /// @param to - The address to call on the rollup.
    /// @param data - The data to send to the rollup.
    /// @param value - The amount of Ether to send on the rollup.
    /// @param gas - The gas limit for the transaction.
    /// @param maxFeePerGas - The maximum fee per gas for the transaction (per EIP-1559).
    /// @custom:emits Transact indicating the transaction to mine on the rollup.
    function enterTransact(
        uint256 rollupChainId,
        address etherRecipient,
        address to,
        bytes calldata data,
        uint256 value,
        uint256 gas,
        uint256 maxFeePerGas
    ) public payable {
        // if msg.value is attached, Enter
        if (msg.value > 0) {
            passage.enter{value: msg.value}(rollupChainId, etherRecipient);
        }

        // ensure per-transact gas limit is respected
        if (gas > perTransactGasLimit) revert PerTransactGasLimit();

        // ensure global transact gas limit is respected
        uint256 gasUsed = transactGasUsed[rollupChainId][block.number];
        if (gasUsed + gas > perBlockGasLimit) revert PerBlockTransactGasLimit();
        transactGasUsed[rollupChainId][block.number] = gasUsed + gas;

        // emit Transact event
        emit Transact(rollupChainId, msg.sender, to, data, value, gas, maxFeePerGas);
    }

    /// @notice Helper to configure gas limits on deploy & via admin function
    function _configureGas(uint256 perBlock, uint256 perTransact) internal {
        perBlockGasLimit = perBlock;
        perTransactGasLimit = perTransact;
        emit GasConfigured(perBlock, perTransact);
    }
}
