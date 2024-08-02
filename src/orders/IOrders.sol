// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.24;

interface IOrders {
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
        /// @dev When emitted on the origin chain, the destination chain for the Output.
        ///      When emitted on the destination chain, the origin chain for the Order containing the Output.
        uint32 chainId;
    }
}
