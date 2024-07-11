// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Passage} from "./Passage.sol";

/// @notice A contract deployed to Host chain that enables transactions from L1 to be sent on an L2.
contract Transactor {
    /// @notice The chainId of rollup that Ether will be sent to by default when entering the rollup via fallback() or receive().
    uint256 public immutable defaultRollupChainId;

    /// @notice The address of the Passage contract, to enable transact + enter.
    Passage public immutable passage;

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

    /// @param _defaultRollupChainId - the chainId of the rollup that Ether will be sent to by default
    ///                                when entering the rollup via fallback() or receive() fns.
    constructor(uint256 _defaultRollupChainId, Passage _passage) {
        defaultRollupChainId = _defaultRollupChainId;
        passage = _passage;
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
    ) public payable {
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
        // emit Transact event
        emit Transact(rollupChainId, msg.sender, to, data, value, gas, maxFeePerGas);
    }
}
