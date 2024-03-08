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
    // @dev The rollup STF MUST NOT apply `submitExit` transactions to the rollup state
    //      UNLESS a corresponding ExitFilled event is emitted on mainnet in the same block.
    // @dev If the user submits multiple exit transactions for the same token in the same rollup block,
    //      the Builder may transfer the cumulative tokenOut to the user in a single ExitFilled event.
    //      The rollup STF will apply the user's exit transactions on the rollup up to the point that sum(tokenOut) is lte the ExitFilled amount.
    // TODO: add option to fulfill ExitOrders with native ETH? or is it sufficient to only allow users to exit via WETH?
    function fulfillExits(ExitOrder[] calldata orders) external {
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

    // @notice Emitted when an exit order is submitted & successfully processed, indicating it was also fulfilled on mainnet.
    // @dev See `submitExit` for parameter docs.
    event Exit(
        address indexed tokenIn_RU,
        address indexed tokenOut_MN,
        address indexed recipient_MN,
        uint256 deadline,
        uint256 amountIn_RU,
        uint256 amountOutMinimum_MN
    );

    // @notice Emitted when tokens or native Ether is swept from the contract.
    // @dev Intended to improve visibility for Builders to ensure Sweep isn't called unexpectedly.
    //      Intentionally does not bother to emit which token(s) were swept, nor their amounts.
    event Sweep(address indexed recipient);

    // @notice Expresses an intent to exit the rollup with ERC20s.
    // @dev Exits are modeled as a swap between two tokens.
    //      tokenIn_RU is provided on the rollup; in exchange,
    //      tokenOut_MN is expected to be received on mainnet.
    //      Exits may "swap" native rollup Ether for mainnet WETH -
    //      two assets that represent the same underlying token and should have roughly the same value -
    //      or they may be a more "true" swap of rollup USDC for mainnet WETH.
    //      Fees paid to the Builders for fulfilling the exit orders
    //      can be included within the "exchange rate" between tokenIn and tokenOut.
    // @dev The Builder claims the tokenIn_RU from the contract by submitting a transaction to `sweep` the tokens within the same block.
    // @dev The Rollup STF MUST NOT apply `submitExit` transactions to the rollup state
    //      UNLESS a sufficient ExitFilled event is emitted on mainnet within the same block.
    // @param tokenIn_RU - The address of the token the user supplies as the input for the trade, which is transferred on the rollup.
    // @param tokenOut_MN - The address of the token the user expects to receive on mainnet.
    // @param recipient_MN - The address of the recipient of tokenOut_MN on mainnet.
    // @param deadline - The deadline by which the exit order must be fulfilled.
    // @param amountIn_RU - The amount of tokenIn_RU the user supplies as the input for the trade, which is transferred on the rollup.
    // @param amountOutMinimum_MN - The minimum amount of tokenOut_MN the user expects to receive on mainnet.
    // @custom:reverts Expired if the deadline has passed.
    // @custom:emits Exit if the exit transaction succeeds.
    function submitExit(
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

    // @notice Expresses an intent to exit the rollup with native Ether.
    // @dev See `submitExit` above for dev details on how exits work.
    // @dev tokenIn_MN is automatically set to address(0), native Ether.
    //      amountIn_RU is set to msg.value.
    // @param tokenOut_MN - The address of the token the user expects to receive on mainnet.
    // @param recipient_MN - The address of the recipient of tokenOut_MN on mainnet.
    // @param deadline - The deadline by which the exit order must be fulfilled.
    // @param amountOutMinimum_MN - The minimum amount of tokenOut_MN the user expects to receive on mainnet.
    // @custom:reverts Expired if the deadline has passed.
    // @custom:emits Exit if the exit transaction succeeds.
    function submitExit(address tokenOut_MN, address recipient_MN, uint256 deadline, uint256 amountOutMinimum_MN)
        external
        payable
    {
        // check that the deadline hasn't passed
        if (block.timestamp >= deadline) revert Expired();

        // emit the exit event
        emit Exit(address(0), tokenOut_MN, recipient_MN, deadline, msg.value, amountOutMinimum_MN);
    }

    // @notice Transfer the entire balance of tokens to the recipient.
    // @dev Called by the Builder within the same block as `submitExit` transactions to claim the amounts of `tokenIn`.
    // @dev Builder MUST ensure that no other account calls `sweep` before them.
    // @param recipient - The address to receive the tokens.
    // @param tokens - The addresses of the tokens to transfer.
    // TODO: should there be more granular control for the builder to specify a different recipient for each token?
    function sweep(address recipient, address[] calldata tokens) public {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            token.transfer(recipient, token.balanceOf(address(this)));
        }
        emit Sweep(recipient);
    }

    // @notice Transfer the entire balance of native Ether to the recipient.
    // @dev Called by the Builder within the same block as `submitExit` transactions to claim the amounts of native Ether.
    // @dev Builder MUST ensure that no other account calls `sweepETH` before them.
    // @param recipient - The address to receive the native Ether.
    function sweepETH(address payable recipient) public {
        recipient.transfer(address(this).balance);
        emit Sweep(recipient);
    }
}
