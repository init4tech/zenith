// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

contract MainnetPassage {
    error MismatchedArrayLengths();

    event Enter(uint256 indexed ruChainId, address indexed rollupRecipient, uint256 amount);
    event ExitFilled(address indexed mainnetRecipient, uint256 amount);

    // BRIDGE INTO ROLLUP
    // permanently locks Ether & emits event
    // NOTE: In response to this event, the rollup STF MUST
    //          1. mint msg.value amount of Ether to `rollupRecipient` on `ruChainId` chain
    function enter(uint256 ruChainId, address rollupRecipient) external payable {
        emit Enter(ruChainId, rollupRecipient, msg.value);
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
    event Cross(uint256 indexed ruChainId, address indexed rollupRecipient, uint256 amount);

    // NOTE: In response to this event, the rollup STF MUST
    //          1. burn msg.value amount of Ether on this rollup
    //          2. mint msg.value amount of Ether to `rollupRecipient` on `ruChainId` chain
    function cross(uint256 ruChainId, address rollupRecipient) external payable {
        emit Cross(ruChainId, rollupRecipient, msg.value);
    }

    // BRIDGE OUT OF ROLLUP
    // tips the block builder with RU Ether, burns the rest of the Ether, emits an event to fill the Exit on mainnet
    // NOTE: This transaction MUST only be regarded by rollup nodes IFF a corresponding
    //       ExitFilled(recipient, amount) event was emitted by mainnet in the same block.
    //       Otherwise, the rollup STF MUST regard this transaction as invalid.
    // NOTE: In response to this event, the rollup STF MUST
    //          1. transfer `tip` on this rollup to the `tipRecipient` specified by the block builder on mainnet
    //          2. burn the rest of the Ether on this rollup
    // TODO: add `tipRecipient` parameter to `submitBlock` function in Zenith.sol
    function exit(address mainnetRecipient, uint256 tip) external payable {
        if (msg.value <= tip) revert InsufficientValue();
        emit Exit(mainnetRecipient, msg.value - tip, tip);
    }
}
