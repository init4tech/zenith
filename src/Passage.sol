// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @notice A contract deployed to Host chain that allows tokens to enter the rollup,
///         and enables Builders to fulfill requests to exchange tokens on the Rollup for tokens on the Host.
contract Passage {
    /// @notice The chainId of rollup that Ether will be sent to by default when entering the rollup via fallback() or receive().
    uint256 immutable defaultRollupChainId;

    /// @notice The address that is allowed to withdraw funds from the contract.
    address public immutable withdrawalAdmin;

    /// @notice Thrown when attempting to withdraw funds if not withdrawal admin.
    error OnlyWithdrawalAdmin();

    /// @notice Emitted when tokens enter the rollup.
    /// @param token - The address of the token entering the rollup.
    /// @param rollupRecipient - The recipient of the token on the rollup.
    /// @param amount - The amount of the token entering the rollup.
    event Enter(uint256 indexed rollupChainId, address indexed token, address indexed rollupRecipient, uint256 amount);

    /// @notice Emitted when the admin withdraws tokens from the contract.
    event Withdrawal(address indexed token, address indexed recipient, uint256 amount);

    /// @notice Emitted when an exit order is fulfilled by the Builder.
    /// @param token - The address of the token transferred to the recipient. address(0) corresponds to native host Ether.
    /// @param hostRecipient - The recipient of the token on host.
    /// @param amount - The amount of the token transferred to the recipient.
    event ExitFulfilled(
        uint256 indexed rollupChainId, address indexed token, address indexed hostRecipient, uint256 amount
    );

    /// @param _defaultRollupChainId - the chainId of the rollup that Ether will be sent to by default
    ///                                when entering the rollup via fallback() or receive() fns.
    constructor(uint256 _defaultRollupChainId, address _withdrawalAdmin) {
        defaultRollupChainId = _defaultRollupChainId;
        withdrawalAdmin = _withdrawalAdmin;
    }

    /// @notice Allows native Ether to enter the rollup by being sent directly to the contract.
    fallback() external payable {
        enter(defaultRollupChainId, msg.sender);
    }

    /// @notice Allows native Ether to enter the rollup by being sent directly to the contract.
    receive() external payable {
        enter(defaultRollupChainId, msg.sender);
    }

    /// @notice Allows native Ether to enter the rollup.
    /// @dev Permanently burns the entire msg.value by locking it in this contract.
    /// @param rollupChainId - The rollup chain to enter.
    /// @param rollupRecipient - The recipient of the Ether on the rollup.
    /// @custom:emits Enter indicating the amount of Ether to mint on the rollup & its recipient.
    function enter(uint256 rollupChainId, address rollupRecipient) public payable {
        emit Enter(rollupChainId, address(0), rollupRecipient, msg.value);
    }

    /// @notice Allows ERC20s to enter the rollup.
    /// @dev Permanently burns the token amount by locking it in this contract.
    /// @param rollupChainId - The rollup chain to enter.
    /// @param rollupRecipient - The recipient of the Ether on the rollup.
    /// @param token - The address of the ERC20 token on the Host.
    /// @param amount - The amount of the ERC20 token to transfer to the rollup.
    /// @custom:emits Enter indicating the amount of tokens to mint on the rollup & its recipient.
    function enter(uint256 rollupChainId, address token, address rollupRecipient, uint256 amount) external payable {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        emit Enter(rollupChainId, token, rollupRecipient, amount);
    }

    /// @notice Allows the admin to withdraw ETH from the contract.
    /// @dev Only the admin can call this function.
    function withdrawEth(address recipient, uint256 amount) external {
        if (msg.sender != withdrawalAdmin) revert OnlyWithdrawalAdmin();
        payable(recipient).transfer(amount);
        emit Withdrawal(address(0), recipient, amount);
    }

    /// @notice Allows the admin to withdraw ERC20 tokens from the contract.
    /// @dev Only the admin can call this function.
    function withdraw(address token, address recipient, uint256 amount) external {
        if (msg.sender != withdrawalAdmin) revert OnlyWithdrawalAdmin();
        IERC20(token).transfer(recipient, amount);
        emit Withdrawal(token, recipient, amount);
    }

    /// @notice Fulfill a rollup Exit order.
    ///         The user calls `exit` on Rollup; the Builder calls `fulfillExit` on Host.
    /// @custom:emits ExitFilled
    /// @param rollupChainId - The chainId of the rollup on which the `submitExit` was called.
    /// @param token - The address of the token to be transferred to the recipient.
    ///                If token is the zero address, the amount is native Ether.
    ///                Corresponds to tokenOut_H in the RollupPassage contract.
    /// @param recipient - The recipient of the token on host.
    ///                    Corresponds to recipient_H in the RollupPassage contract.
    /// @param amount - The amount of the token to be transferred to the recipient.
    ///                 Corresponds to one or more amountOutMinimum_H in the RollupPassage contract.
    function fulfillExit(uint256 rollupChainId, address token, address recipient, uint256 amount) external {
        IERC20(token).transferFrom(msg.sender, recipient, amount);
        emit ExitFulfilled(rollupChainId, token, recipient, amount);
    }

    /// @notice Fulfill a rollup Exit order
    ///         The user calls `exit` on Rollup; the Builder calls `fulfillExit` on Host.
    /// @custom:emits ExitFilled
    /// @param recipient - The recipient of the token on host.
    ///                    Corresponds to recipient_H in the RollupPassage contract.
    function fulfillExitEth(uint256 rollupChainId, address recipient) external payable {
        payable(recipient).transfer(msg.value);
        emit ExitFulfilled(rollupChainId, address(0), recipient, msg.value);
    }
}

/// @notice A contract deployed to the Rollup that allows users to atomically exchange tokens on the Rollup for tokens on the Host.
contract RollupPassage {
    /// @notice Thrown when an exit transaction is submitted with a deadline that has passed.
    error OrderExpired();

    /// @notice Emitted when an exit order is successfully processed, indicating it was also fulfilled on host.
    /// @dev See `exit` for parameter docs.
    event Exit(
        address indexed tokenIn_RU,
        address indexed tokenOut_H,
        address indexed recipient_H,
        uint256 deadline,
        uint256 amountIn_RU,
        uint256 amountOutMinimum_H
    );

    /// @notice Emitted when tokens or native Ether is swept from the contract.
    /// @dev Intended to improve visibility for Builders to ensure Sweep isn't called unexpectedly.
    ///      Intentionally does not bother to emit which token(s) were swept, nor their amounts.
    event Sweep(address indexed token, address indexed recipient, uint256 amount);

    /// @notice Request to exit the rollup with ERC20s.
    /// @dev Exits are modeled as a swap between two tokens.
    ///      tokenIn_RU is provided on the rollup; in exchange,
    ///      tokenOut_H is expected to be received on host.
    ///      Exits may "swap" native rollup Ether for host WETH -
    ///      two assets that represent the same underlying token and should have roughly the same value -
    ///      or they may be a more "true" swap of rollup USDC for host WETH.
    ///      Fees paid to the Builders for fulfilling the exit orders
    ///      can be included within the "exchange rate" between tokenIn and tokenOut.
    /// @dev The Builder claims the tokenIn_RU from the contract by submitting a transaction to `sweep` the tokens within the same block.
    /// @dev The Rollup STF MUST NOT apply `submitExit` transactions to the rollup state
    ///      UNLESS a sufficient ExitFilled event is emitted on host within the same block.
    /// @param tokenIn_RU - The address of the token the user supplies as the input on the rollup for the trade.
    /// @param tokenOut_H - The address of the token the user expects to receive on host.
    /// @param recipient_H - The address of the recipient of tokenOut_H on host.
    /// @param deadline - The deadline by which the exit order must be fulfilled.
    /// @param amountIn_RU - The amount of tokenIn_RU the user supplies as the input on the rollup for the trade.
    /// @param amountOutMinimum_H - The minimum amount of tokenOut_H the user expects to receive on host.
    /// @custom:reverts Expired if the deadline has passed.
    /// @custom:emits Exit if the exit transaction succeeds.
    function exit(
        address tokenIn_RU,
        address tokenOut_H,
        address recipient_H,
        uint256 deadline,
        uint256 amountIn_RU,
        uint256 amountOutMinimum_H
    ) external {
        // check that the deadline hasn't passed
        if (block.timestamp >= deadline) revert OrderExpired();

        IERC20(tokenIn_RU).transferFrom(msg.sender, address(this), amountIn_RU);

        // emit the exit event
        emit Exit(tokenIn_RU, tokenOut_H, recipient_H, deadline, amountIn_RU, amountOutMinimum_H);
    }

    /// @notice Request exit the rollup with native Ether.
    /// @dev See `exit` docs above for dev details on exits.
    /// @dev tokenIn_RU is set to address(0), native rollup Ether.
    ///      amountIn_RU is set to msg.value.
    /// @param tokenOut_H - The address of the token the user expects to receive on host.
    /// @param recipient_H - The address of the recipient of tokenOut_H on host.
    /// @param deadline - The deadline by which the exit order must be fulfilled.
    /// @param amountOutMinimum_H - The minimum amount of tokenOut_H the user expects to receive on host.
    /// @custom:reverts Expired if the deadline has passed.
    /// @custom:emits Exit if the exit transaction succeeds.
    function exitEth(address tokenOut_H, address recipient_H, uint256 deadline, uint256 amountOutMinimum_H)
        external
        payable
    {
        // check that the deadline hasn't passed
        if (block.timestamp >= deadline) revert OrderExpired();

        // emit the exit event
        emit Exit(address(0), tokenOut_H, recipient_H, deadline, msg.value, amountOutMinimum_H);
    }

    /// @notice Transfer the entire balance of ERC20 tokens to the recipient.
    /// @dev Called by the Builder within the same block as users' `exit` transactions
    ///      to claim the amounts of `tokenIn`.
    /// @dev Builder MUST ensure that no other account calls `sweep` before them.
    /// @param token - The token to transfer.
    /// @param recipient - The address to receive the tokens.
    function sweep(address token, address recipient) public {
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(recipient, balance);
        emit Sweep(token, recipient, balance);
    }

    /// @notice Transfer the entire balance of native Ether to the recipient.
    /// @dev Called by the Builder within the same block as users' `exit` transactions
    ///      to claim the amounts of native Ether.
    /// @dev Builder MUST ensure that no other account calls `sweepETH` before them.
    /// @param recipient - The address to receive the native Ether.
    function sweepEth(address payable recipient) public {
        uint256 balance = address(this).balance;
        recipient.transfer(balance);
        emit Sweep(address(0), recipient, balance);
    }
}
