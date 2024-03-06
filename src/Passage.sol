// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// import IERC20 from OpenZeppelin
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

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
    // TODO: add more info?
    error Expired();

    event Exit(
        address indexed tokenIn_RU,
        address indexed tokenOut_MN,
        address indexed recipient_MN,
        uint256 deadline,
        uint256 amountIn_RU,
        uint256 amountOutMinimum_MN
    );

    // BRIDGE OUT OF ROLLUP
    // transfers some token input on the rollup, which is claimable by the builder via `sweep`
    // expects a minimum token output on mainnet, which will be filled by the builder

    // emits an event to signal a required exit on mainnet
    // NOTE: This transaction MUST only be regarded by rollup nodes IFF a corresponding
    //       ExitFilled(recipient, amount) event was emitted by mainnet in the same block.
    //       Otherwise, the rollup STF MUST regard this transaction as invalid.

    // user transfers their tokens / ETH into the contract as part of this function
    // user specifies what they need to receive on mainnet for the transfer to be applied by RU STF
    // builder sends the output on mainnet
    // builder adds the user's transactions to RU + sweep() function, which sends all inputs to themselves at the end of the block
    function exitExactInput(
        address tokenIn_RU,
        address tokenOut_MN,
        address recipient_MN,
        uint256 deadline,
        uint256 amountIn_RU,
        uint256 amountOutMinimum_MN
    ) external {
        // check that the deadline hasn't passed
        if (block.timestamp >= deadline) revert Expired();

        // transfer the tokens from the user to the contract
        IERC20(tokenIn_RU).transferFrom(msg.sender, address(this), amountIn_RU);

        // emit the exit event
        emit Exit(tokenIn_RU, tokenOut_MN, recipient_MN, deadline, amountIn_RU, amountOutMinimum_MN);
    }

    // SWEEP
    // called by builder to pay themselves users' inputs
    //      NOTE: builder MUST NOT include transactions that call sweep() before they do
    //      NOTE: builder MUST check that user doesn't call sweep() within same transaction as this function
    //      NOTE: builder SHOULD call sweep() directly after the transaction that calls this function
    // TODO: should there be more granular control for the builder to specify a different recipient for each token?
    function sweep(address recipient, address[] calldata tokens) public {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            token.transfer(recipient, token.balanceOf(address(this)));
        }
    }
}
