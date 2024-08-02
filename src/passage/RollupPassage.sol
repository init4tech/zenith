// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.24;

import {PassagePermit2} from "./PassagePermit2.sol";
import {UsesPermit2} from "../UsesPermit2.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Burnable} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ReentrancyGuardTransient} from "openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol";

/// @notice Enables tokens to Exit the rollup.
contract RollupPassage is PassagePermit2, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    /// @notice Emitted when native Ether exits the rollup.
    /// @param hostRecipient - The *requested* recipient of tokens on the host chain.
    /// @param amount - The amount of Ether exiting the rollup.
    event Exit(address indexed hostRecipient, uint256 amount);

    /// @notice Emitted when ERC20 tokens exit the rollup.
    /// @param hostRecipient - The *requested* recipient of tokens on the host chain.
    /// @param token - The token exiting the rollup.
    /// @param amount - The amount of ERC20s exiting the rollup.
    event ExitToken(address indexed hostRecipient, address indexed token, uint256 amount);

    constructor(address _permit2) UsesPermit2(_permit2) {}

    /// @notice Allows native Ether to exit the rollup by being sent directly to the contract.
    fallback() external payable {
        exit(msg.sender);
    }

    /// @notice Allows native Ether to exit the rollup by being sent directly to the contract.
    receive() external payable {
        exit(msg.sender);
    }

    /// @notice Allows native Ether to exit the rollup.
    /// @param hostRecipient - The *requested* recipient of tokens on the host chain.
    /// @custom:emits Exit indicating the amount of Ether that was locked on the rollup & the requested host recipient.
    function exit(address hostRecipient) public payable {
        if (msg.value == 0) return;
        emit Exit(hostRecipient, msg.value);
    }

    /// @notice Allows ERC20 tokens to exit the rollup.
    /// @param hostRecipient - The *requested* recipient of tokens on the host chain.
    /// @param token - The rollup address of the token exiting the rollup.
    /// @param amount - The amount of tokens exiting the rollup.
    /// @custom:emits ExitToken
    function exitToken(address hostRecipient, address token, uint256 amount) external nonReentrant {
        // transfer tokens to this contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        // burn and emit
        _exitToken(hostRecipient, token, amount);
    }

    /// @notice Allows ERC20 tokens to exit the rollup.
    /// @param hostRecipient - The *requested* recipient of tokens on the host chain.
    /// @param permit2 - The Permit2 information, including token & amount.
    /// @custom:emits ExitToken
    function exitTokenPermit2(address hostRecipient, PassagePermit2.Permit2 calldata permit2) external nonReentrant {
        // transfer tokens to this contract
        _permitWitnessTransferFrom(exitWitness(hostRecipient), permit2);
        // burn and emit
        _exitToken(hostRecipient, permit2.permit.permitted.token, permit2.permit.permitted.amount);
    }

    /// @notice Shared functionality for tokens exiting rollup.
    function _exitToken(address hostRecipient, address token, uint256 amount) internal {
        if (amount == 0) return;
        ERC20Burnable(token).burn(amount);
        emit ExitToken(hostRecipient, token, amount);
    }
}
