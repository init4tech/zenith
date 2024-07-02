// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @notice Tokens sent by the swapper as inputs to the order
/// @dev From ERC-7683
struct Input {
    /// @dev The address of the ERC20 token on the origin chain
    address token;
    /// @dev The amount of the token to be sent
    uint256 amount;
}

/// @notice Tokens that must be receive for a valid order fulfillment
/// @dev From ERC-7683
struct Output {
    /// @dev The address of the ERC20 token on the destination chain
    /// @dev address(0) used as a sentinel for the native token
    address token;
    /// @dev The amount of the token to be sent
    uint256 amount;
    /// @dev The address to receive the output tokens
    address recipient;
    /// @dev The destination chain for this output
    uint32 chainId;
}

/// @notice Contract capable of processing fulfillment of intent-based Orders.
abstract contract OrderDestination {
    /// @notice Emitted when an Order's Output is sent to the recipient.
    /// @dev There may be multiple Outputs per Order.
    /// @param originChainId - The chainId on which the Order was initiated.
    /// @param recipient - The recipient of the token.
    /// @param token - The address of the token transferred to the recipient. address(0) corresponds to native Ether.
    /// @param amount - The amount of the token transferred to the recipient.
    event OutputFilled(uint256 indexed originChainId, address indexed recipient, address indexed token, uint256 amount);

    /// @notice Send the Output(s) of an Order to fulfill it.
    ///         The user calls `initiate` on a rollup; the Builder calls `fill` on the target chain for each Output.
    /// @custom:emits OutputFilled
    /// @param originChainId - The chainId on which the Order was initiated.
    /// @param recipient - The recipient of the token.
    /// @param token - The address of the token to be transferred to the recipient.
    ///                address(0) corresponds to native Ether.
    /// @param amount - The amount of the token to be transferred to the recipient.
    function fill(uint256 originChainId, address recipient, address token, uint256 amount) external payable {
        if (token == address(0)) {
            require(amount == msg.value);
            payable(recipient).transfer(msg.value);
        } else {
            IERC20(token).transferFrom(msg.sender, recipient, amount);
        }
        emit OutputFilled(originChainId, recipient, token, amount);
    }
}

/// @notice Contract capable of registering initiation of intent-based Orders.
abstract contract OrderOrigin {
    /// @notice Thrown when an Order is submitted with a deadline that has passed.
    error OrderExpired();

    /// @notice Thrown when trying to call `sweep` if not the Builder of the block.
    error OnlyBuilder();

    /// @notice Emitted when an Order is submitted for fulfillment.
    event Order(uint256 deadline, Input[] inputs, Output[] outputs);

    /// @notice Emitted when tokens or native Ether is swept from the contract.
    /// @dev Intended to improve visibility for Builders to ensure Sweep isn't called unexpectedly.
    ///      Intentionally does not bother to emit which token(s) were swept, nor their amounts.
    event Sweep(address indexed recipient, address indexed token, uint256 amount);

    /// @notice Request to swap ERC20s.
    /// @dev inputs are provided on the rollup; in exchange,
    ///      outputs are expected to be received on the target chain(s).
    /// @dev Fees paid to the Builders for fulfilling the Orders
    ///      can be included within the "exchange rate" between inputs and outputs.
    /// @dev The Builder claims the inputs from the contract by submitting `sweep` transactions within the same block.
    /// @dev The Rollup STF MUST NOT apply `initiate` transactions to the rollup state
    ///      UNLESS the outputs are delivered on the target chains within the same block.
    /// @param deadline - The deadline at or before which the Order must be fulfilled.
    /// @param inputs - The token amounts offered by the swapper in exchange for the outputs.
    /// @param outputs - The token amounts that must be received on their target chain(s) in order for the Order to be executed.
    /// @custom:reverts OrderExpired if the deadline has passed.
    /// @custom:emits Order if the transaction mines.
    function initiate(uint256 deadline, Input[] memory inputs, Output[] memory outputs) external payable {
        // check that the deadline hasn't passed
        if (block.timestamp > deadline) revert OrderExpired();

        // transfer inputs to this contract
        _transferInputs(inputs);

        // emit
        emit Order(deadline, inputs, outputs);
    }

    /// @notice Transfer the Order inputs to this contract, where they can be collected by the Order filler.
    function _transferInputs(Input[] memory inputs) internal {
        uint256 value = msg.value;
        for (uint256 i; i < inputs.length; i++) {
            if (inputs[i].token == address(0)) {
                // this line should underflow if there's an attempt to spend more ETH than is attached to the transaction
                value -= inputs[i].amount;
            } else {
                IERC20(inputs[i].token).transferFrom(msg.sender, address(this), inputs[i].amount);
            }
        }
    }

    /// @notice Transfer the entire balance of ERC20 tokens to the recipient.
    /// @dev Called by the Builder within the same block as users' `initiate` transactions
    ///      to claim the `inputs`.
    /// @dev Builder MUST call `sweep` atomically with `fill` (claim Inputs atomically with sending Outputs).
    /// @param recipient - The address to receive the tokens.
    /// @param token - The token to transfer.
    /// @custom:emits Sweep
    /// @custom:reverts OnlyBuilder if called by non-block builder
    function sweep(address recipient, address token) public {
        if (msg.sender != block.coinbase) revert OnlyBuilder();
        // send ETH or tokens
        uint256 balance;
        if (token == address(0)) {
            balance = address(this).balance;
            payable(recipient).transfer(balance);
        } else {
            balance = IERC20(token).balanceOf(address(this));
            IERC20(token).transfer(recipient, balance);
        }
        emit Sweep(recipient, token, balance);
    }
}

contract HostOrders is OrderDestination {}

contract RollupOrders is OrderOrigin, OrderDestination {}
