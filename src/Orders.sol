// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Permit2Batch, UsesPermit2} from "./UsesPermit2.sol";
import {IOrders} from "./interfaces/IOrders.sol";

/// @notice Contract capable of processing fulfillment of intent-based Orders.
abstract contract OrderDestination is IOrders, UsesPermit2 {
    /// @notice Emitted when Order Outputs are sent to their recipients.
    /// @dev NOTE that here, Output.chainId denotes the *origin* chainId.
    event Filled(Output[] outputs);

    /// @notice Fill any number of Order(s), by transferring their Output(s).
    /// @dev Filler may aggregate multiple Outputs with the same (`chainId`, `recipient`, `token`) into a single Output with the summed `amount`.
    /// @dev NOTE that here, Output.chainId denotes the *origin* chainId.
    /// @param outputs - The Outputs to be transferred.
    /// @custom:emits Filled
    function fill(Output[] memory outputs) external payable {
        // transfer outputs
        _transferOutputs(outputs);

        // emit
        emit Filled(outputs);
    }

    /// @notice Transfer the Order Outputs to their recipients.
    function _transferOutputs(Output[] memory outputs) internal {
        uint256 value = msg.value;
        for (uint256 i; i < outputs.length; i++) {
            if (outputs[i].token == address(0)) {
                // this line should underflow if there's an attempt to spend more ETH than is attached to the transaction
                value -= outputs[i].amount;
                payable(outputs[i].recipient).transfer(outputs[i].amount);
            } else {
                IERC20(outputs[i].token).transferFrom(msg.sender, outputs[i].recipient, outputs[i].amount);
            }
        }
    }

    /// @notice Fill any number of Order(s), by transferring their Output(s) via permit2 signed batch transfer.
    /// @dev Can only provide ERC20 tokens as Outputs.
    /// @dev Filler may aggregate multiple Outputs with the same (`chainId`, `recipient`, `token`) into a single Output with the summed `amount`.
    /// @dev the permit2 signer is the Filler providing the Outputs.
    /// @dev the permit2 `permitted` tokens MUST match provided Outputs.
    /// @dev Filler MUST submit `fill` and `intitiate` within an atomic bundle.
    /// @dev NOTE that here, Output.chainId denotes the *origin* chainId.
    /// @param outputs - The Outputs to be transferred. signed over via permit2 witness.
    /// @param permit2 - the permit2 details, signer, and signature.
    /// @custom:emits Filled
    function fillPermit2(Output[] memory outputs, Permit2Batch calldata permit2) external {
        // transfer all tokens to the Output recipients via permit2 (includes check on nonce & deadline)
        _permitWitnessTransferFrom(outputs, _fillTransferDetails(outputs, permit2.permit.permitted), permit2);

        // emit
        emit Filled(outputs);
    }
}

/// @notice Contract capable of registering initiation of intent-based Orders.
abstract contract OrderOrigin is IOrders, UsesPermit2 {
    /// @notice Thrown when an Order is submitted with a deadline that has passed.
    error OrderExpired();

    /// @notice Emitted when an Order is submitted for fulfillment.
    /// @dev NOTE that here, Output.chainId denotes the *destination* chainId.
    event Order(uint256 deadline, Input[] inputs, Output[] outputs);

    /// @notice Emitted when tokens or native Ether is swept from the contract.
    /// @dev Intended to improve visibility for Builders to ensure Sweep isn't called unexpectedly.
    ///      Intentionally does not bother to emit which token(s) were swept, nor their amounts.
    event Sweep(address indexed recipient, address indexed token, uint256 amount);

    /// @notice Initiate an Order.
    /// @dev Filler MUST submit `fill` and `intitiate` + `sweep` within an atomic bundle.
    /// @dev NOTE that here, Output.chainId denotes the *target* chainId.
    /// @dev inputs are provided on the rollup; in exchange,
    ///      outputs are expected to be received on the target chain(s).
    /// @dev The Rollup STF MUST NOT apply `initiate` transactions to the rollup state
    ///      UNLESS the outputs are delivered on the target chains within the same block.
    /// @dev Fees paid to the Builders for fulfilling the Orders
    ///      can be included within the "exchange rate" between inputs and outputs.
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

    /// @notice Transfer the Order inputs to this contract, where they can be collected by the Order filler via `sweep`.
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

    /// @notice Initiate an Order, transferring Input tokens to the Filler via permit2 signed batch transfer.
    /// @dev Can only provide ERC20 tokens as Inputs.
    /// @dev the permit2 signer is the swapper providing the Input tokens in exchange for the Outputs.
    /// @dev Filler MUST submit `fill` and `intitiate` within an atomic bundle.
    /// @dev NOTE that here, Output.chainId denotes the *target* chainId.
    /// @param tokenRecipient - the recipient of the Input tokens, provided by msg.sender (un-verified by permit2).
    /// @param outputs - the Outputs required in exchange for the Input tokens. signed over via permit2 witness.
    /// @param permit2 - the permit2 details, signer, and signature.
    function initiatePermit2(address tokenRecipient, Output[] memory outputs, Permit2Batch calldata permit2) external {
        // transfer all tokens to the tokenRecipient via permit2 (includes check on nonce & deadline)
        _permitWitnessTransferFrom(outputs, _initiateTransferDetails(tokenRecipient, permit2.permit.permitted), permit2);

        // emit
        emit Order(permit2.permit.deadline, _inputs(permit2.permit.permitted), outputs);
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

contract HostOrders is OrderDestination {
    constructor(address _permit2) UsesPermit2(_permit2) {}
}

contract RollupOrders is OrderOrigin, OrderDestination {
    constructor(address _permit2) UsesPermit2(_permit2) {}
}
