// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.24;

import {OrdersPermit2} from "./OrdersPermit2.sol";
import {IOrders} from "./IOrders.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {ReentrancyGuardTransient} from "openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol";

/// @notice Contract capable of processing fulfillment of intent-based Orders.
abstract contract OrderDestination is IOrders, OrdersPermit2, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;
    using Address for address payable;

    /// @notice Emitted when Order Outputs are sent to their recipients.
    /// @dev NOTE that here, Output.chainId denotes the *origin* chainId.
    event Filled(Output[] outputs);

    /// @notice Fill any number of Order(s), by transferring their Output(s).
    /// @dev Filler may aggregate multiple Outputs with the same (`chainId`, `recipient`, `token`) into a single Output with the summed `amount`.
    /// @dev NOTE that here, Output.chainId denotes the *origin* chainId.
    /// @param outputs - The Outputs to be transferred.
    /// @custom:emits Filled
    function fill(Output[] memory outputs) external payable nonReentrant {
        // transfer outputs
        _transferOutputs(outputs);

        // emit
        emit Filled(outputs);
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
    function fillPermit2(Output[] memory outputs, OrdersPermit2.Permit2Batch calldata permit2) external nonReentrant {
        // transfer all tokens to the Output recipients via permit2 (includes check on nonce & deadline)
        _permitWitnessTransferFrom(
            outputWitness(outputs), _fillTransferDetails(outputs, permit2.permit.permitted), permit2
        );

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
                payable(outputs[i].recipient).sendValue(outputs[i].amount);
            } else {
                IERC20(outputs[i].token).safeTransferFrom(msg.sender, outputs[i].recipient, outputs[i].amount);
            }
        }
    }
}
