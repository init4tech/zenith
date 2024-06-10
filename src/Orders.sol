// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @notice Contract capable of processing fulfillment of intent-based Orders.
abstract contract OrderDestination {
    /// @notice Emitted when an swap order is fulfilled by the Builder.
    /// @param originChainId - The chainId on which the swap order was submitted.
    /// @param token - The address of the token transferred to the recipient. address(0) corresponds to native Ether.
    /// @param recipient - The recipient of the token.
    /// @param amount - The amount of the token transferred to the recipient.
    event SwapFulfilled(
        uint256 indexed originChainId, address indexed token, address indexed recipient, uint256 amount
    );

    /// @notice Fulfill a rollup Swap order.
    ///         The user calls `swap` on a rollup; the Builder calls `fulfillSwap` on the target chain.
    /// @custom:emits SwapFulfilled
    /// @param originChainId - The chainId of the rollup on which `swap` was called.
    /// @param token - The address of the token to be transferred to the recipient.
    ///                address(0) corresponds to native Ether.
    /// @param recipient - The recipient of the token.
    /// @param amount - The amount of the token to be transferred to the recipient.
    function fulfillSwap(uint256 originChainId, address token, address recipient, uint256 amount) external payable {
        if (token == address(0)) {
            require(amount == msg.value);
            payable(recipient).transfer(msg.value);
        } else {
            IERC20(token).transferFrom(msg.sender, recipient, amount);
        }
        emit SwapFulfilled(originChainId, token, recipient, amount);
    }
}

/// @notice Contract capable of registering initiation of intent-based Orders.
abstract contract OrderOrigin {
    /// @notice Thrown when an swap transaction is submitted with a deadline that has passed.
    error OrderExpired();

    /// @notice Emitted when an swap order is successfully processed, indicating it was also fulfilled on the target chain.
    /// @dev See `swap` for parameter docs.
    event Swap(
        uint256 indexed targetChainId,
        address indexed tokenIn,
        address indexed tokenOut,
        address recipient,
        uint256 deadline,
        uint256 amountIn,
        uint256 amountOut
    );

    /// @notice Emitted when tokens or native Ether is swept from the contract.
    /// @dev Intended to improve visibility for Builders to ensure Sweep isn't called unexpectedly.
    ///      Intentionally does not bother to emit which token(s) were swept, nor their amounts.
    event Sweep(address indexed token, address indexed recipient, uint256 amount);

    /// @notice Request to swap ERC20s.
    /// @dev tokenIn is provided on the rollup; in exchange,
    ///      tokenOut is expected to be received on targetChainId.
    /// @dev targetChainId may be the current chainId, the Host chainId, or..
    /// @dev Fees paid to the Builders for fulfilling the swap orders
    ///      can be included within the "exchange rate" between tokenIn and tokenOut.
    /// @dev The Builder claims the tokenIn from the contract by submitting a transaction to `sweep` the tokens within the same block.
    /// @dev The Rollup STF MUST NOT apply `swap` transactions to the rollup state
    ///      UNLESS a sufficient SwapFulfilled event is emitted on the target chain within the same block.
    /// @param targetChainId - The chain on which tokens should be output.
    /// @param tokenIn - The address of the token the user supplies as the input on the rollup for the trade.
    /// @param tokenOut - The address of the token the user expects to receive on the target chain.
    /// @param recipient - The address of the recipient of tokenOut on the target chain.
    /// @param deadline - The deadline by which the swap order must be fulfilled.
    /// @param amountIn - The amount of tokenIn the user supplies as the input on the rollup for the trade.
    /// @param amountOut - The minimum amount of tokenOut the user expects to receive on the target chain.
    /// @custom:reverts Expired if the deadline has passed.
    /// @custom:emits Swap if the swap transaction succeeds.
    function swap(
        uint256 targetChainId,
        address tokenIn,
        address tokenOut,
        address recipient,
        uint256 deadline,
        uint256 amountIn,
        uint256 amountOut
    ) external payable {
        // check that the deadline hasn't passed
        if (block.timestamp >= deadline) revert OrderExpired();

        if (tokenIn == address(0)) {
            require(amountIn == msg.value);
        } else {
            IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        }

        // emit the swap event
        emit Swap(targetChainId, tokenIn, tokenOut, recipient, deadline, amountIn, amountOut);
    }

    /// @notice Transfer the entire balance of ERC20 tokens to the recipient.
    /// @dev Called by the Builder within the same block as users' `swap` transactions
    ///      to claim the amounts of `tokenIn`.
    /// @dev Builder MUST ensure that no other account calls `sweep` before them.
    /// @param token - The token to transfer.
    /// @param recipient - The address to receive the tokens.
    function sweep(address token, address recipient) public {
        uint256 balance;
        if (token == address(0)) {
            balance = address(this).balance;
            payable(recipient).transfer(balance);
        } else {
            balance = IERC20(token).balanceOf(address(this));
            IERC20(token).transfer(recipient, balance);
        }
        emit Sweep(token, recipient, balance);
    }
}

contract HostOrders is OrderDestination {}

contract RollupOrders is OrderOrigin, OrderDestination {}
