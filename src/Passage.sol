// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

contract MainnetPassage {
    error MismatchedArrayLengths();

    event Enter(address indexed rollupRecipient, uint256 amount);
    event ExitFilled(address indexed mainnetRecipient, uint256 amount);

    fallback() external payable {
        enter(msg.sender);
    }

    receive() external payable {
        enter(msg.sender);
    }

    // BRIDGE INTO ROLLUP
    // permanently locks Ether & emits event
    function enter(address rollupRecipient) public payable {
        emit Enter(rollupRecipient, msg.value);
    }

    // BRIDGE OUT OF ROLLUP
    // fwds Ether from block builder to recipients to fill Exit events
    function fillExits(address[] calldata mainnetRecipients, uint256[] calldata amounts) external payable {
        if (mainnetRecipients.length != amounts.length) revert MismatchedArrayLengths();

        for (uint256 i = 0; i < mainnetRecipients.length; i++) {
            payable(mainnetRecipients[i]).transfer(amounts[i]);
            emit ExitFilled(mainnetRecipients[i], amounts[i]);
        }
    }
}

contract RollupPassage {
    error InsufficientValue();

    event Exit(address indexed mainnetRecipient, uint256 amount, uint256 tip);

    // BRIDGE OUT OF ROLLUP
    // tips the block builder with RU Ether, burns the rest of the Ether, emits an event to fill the Exit on mainnet
    // NOTE: This transaction MUST only be regarded by rollup nodes IFF a corresponding
    //       ExitFilled(recipient, amount) event was emitted by mainnet in the same block.
    //       Otherwise, the rollup STF MUST regard this transaction as invalid.
    //       In response to this event, the rollup STF MUST
    //          1. transfer `tip` to the `tipRecipient` specified by the block builder
    //          2. burn the rest of the Ether
    // TODO: add `tipRecipient` parameter to `submitBlock` function in Zenith.sol
    function exit(address mainnetRecipient, uint256 tip) external payable {
        if (msg.value <= tip) revert InsufficientValue();
        emit Exit(mainnetRecipient, msg.value - tip, tip);
    }
}
