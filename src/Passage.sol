// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// import IERC20 from OpenZeppelin
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract MainnetPassage {
    // @notice Thrown when attempting to fill an exit order with a deadline that has passed.
    error Expired();

    // @notice Emitted when tokens enter the rollup.
    // @param token - The address of the token entering the rollup.
    // @param rollupRecipient - The recipient of the token on the rollup.
    // @param amount - The amount of the token entering the rollup.
    event Enter(address indexed token, address indexed rollupRecipient, uint256 amount);

    // @notice Emitted when an exit order is fulfilled by the Builder.
    // @param token - The address of the token transferred to the recipient.
    // @param mainnetRecipient - The recipient of the token on mainnet.
    // @param amount - The amount of the token transferred to the recipient.
    event ExitFilled(address indexed token, address indexed mainnetRecipient, uint256 amount);

    // @notice Details of an exit order to be fulfilled by the Builder.
    // @param token - The address of the token to be transferred to the recipient.
    //                If token is the zero address, the amount is native Ether.
    //                Corresponds to tokenOut_MN in the RollupPassage contract.
    // @param recipient - The recipient of the token on mainnet.
    //                    Corresponds to recipient_MN in the RollupPassage contract.
    // @param amount - The amount of the token to be transferred to the recipient.
    //                 Corresponds to one or more amountOutMinimum_MN in the RollupPassage contract.
    // @param deadline - The deadline by which the exit order must be fulfilled.
    //                   Corresponds to deadline in the RollupPassage contract.
    //                   If the ExitOrder is a combination of multiple orders, the deadline SHOULD be the latest of all orders.
    struct ExitOrder {
        address token;
        address recipient;
        uint256 amount;
        uint256 deadline;
    }

    // @notice Allows native Ether to enter the rollup by being sent directly to the contract.
    fallback() external payable {
        enter(msg.sender);
    }

    // @notice Allows native Ether to enter the rollup by being sent directly to the contract.
    receive() external payable {
        enter(msg.sender);
    }

    // @notice Allows native Ether to enter the rollup.
    // @dev Permanently burns the entire msg.value by locking it in this contract.
    // @param rollupRecipient - The recipient of the Ether on the rollup.
    // @custom:emits Enter indicatig the amount of Ether to mint on the rollup & its recipient.
    function enter(address rollupRecipient) public payable {
        emit Enter(address(0), rollupRecipient, msg.value);
    }

    // @notice Fulfills exit orders by transferring tokenOut to the recipient
    // @param orders The exit orders to fulfill
    // @custom:emits ExitFilled for each exit order fulfilled.
    // @dev Called by the Builder atomically with a transaction calling `submitBlock`.
    //      The user-submitted transactions initiating the ExitOrders on the rollup
    //      must be included by the Builder in the rollup block submitted via `submitBlock`.
    // @dev The user transfers tokenIn on the rollup, and receives tokenOut on mainnet.
    // @dev The Builder receives tokenIn on the rollup, and transfers tokenOut to the user on mainnet.
    // @dev The rollup STF MUST NOT apply `initiateExit` transactions to the rollup state
    //      UNLESS a corresponding ExitFilled event is emitted on mainnet in the same block.
    // @dev If the user initiates multiple exit transactions for the same token in the same rollup block,
    //      the Builder may transfer the cumulative tokenOut to the user in a single ExitFilled event.
    //      The rollup STF will apply the user's transactions on the rollup, up to the point that sum(tokenOut) is lte the ExitFilled amount.
    // TODO: add option to fulfill ExitOrders with native ETH? or is it sufficient to only allow users to exit via WETH?
    function fulfillExitOrders(ExitOrder[] calldata orders) external {
        for (uint256 i = 0; i < orders.length; i++) {
            ExitOrder memory order = orders[i];
            // check that the deadline hasn't passed
            if (block.timestamp >= order.deadline) revert Expired();
            // transfer tokens to the recipient
            IERC20(order.token).transferFrom(msg.sender, order.recipient, order.amount);
            // emit
            emit ExitFilled(order.token, order.recipient, order.amount);
        }
    }
}

contract RollupPassage {
    // @notice Thrown when an exit tranaction is submitted with a deadline that has passed.
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

    // EXIT TOKENS
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

    // EXIT ETH
    function exitExactInput(address tokenOut_MN, address recipient_MN, uint256 deadline, uint256 amountOutMinimum_MN)
        external
        payable
    {
        // check that the deadline hasn't passed
        if (block.timestamp >= deadline) revert Expired();

        // emit the exit event
        emit Exit(address(0), tokenOut_MN, recipient_MN, deadline, msg.value, amountOutMinimum_MN);
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

    function sweepETH(address payable recipient) public {
        recipient.transfer(address(this).balance);
    }
}
