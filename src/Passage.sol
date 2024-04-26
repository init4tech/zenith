// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// import IERC20 from OpenZeppelin
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @notice A contract deployed to Host chain that allows tokens to enter the rollup,
///         and enables Builders to fulfill requests to exchange tokens on the Rollup for tokens on the Host.
contract HostPassage {
    /// @notice The chainId of the default rollup chain.
    uint256 immutable defaultRollupChainId;

    /// @notice Thrown when attempting to fulfill an exit order with a deadline that has passed.
    error OrderExpired();

    /// @notice Emitted when tokens enter the rollup.
    /// @param token - The address of the token entering the rollup.
    /// @param rollupRecipient - The recipient of the token on the rollup.
    /// @param amount - The amount of the token entering the rollup.
    event Enter(uint256 rollupChainId, address indexed token, address indexed rollupRecipient, uint256 amount);

    /// @notice Emitted when an exit order is fulfilled by the Builder.
    /// @param token - The address of the token transferred to the recipient.
    /// @param hostRecipient - The recipient of the token on host.
    /// @param amount - The amount of the token transferred to the recipient.
    event ExitFilled(uint256 rollupChainId, address indexed token, address indexed hostRecipient, uint256 amount);

    /// @notice Details of an exit order to be fulfilled by the Builder.
    /// @param token - The address of the token to be transferred to the recipient.
    ///                If token is the zero address, the amount is native Ether.
    ///                Corresponds to tokenOut_H in the RollupPassage contract.
    /// @param recipient - The recipient of the token on host.
    ///                    Corresponds to recipient_H in the RollupPassage contract.
    /// @param amount - The amount of the token to be transferred to the recipient.
    ///                 Corresponds to one or more amountOutMinimum_H in the RollupPassage contract.
    struct ExitOrder {
        uint256 rollupChainId;
        address token;
        address recipient;
        uint256 amount;
    }

    constructor(uint256 _defaultRollupChainId) {
        defaultRollupChainId = _defaultRollupChainId;
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
    /// @custom:emits Enter indicatig the amount of Ether to mint on the rollup & its recipient.
    function enter(uint256 rollupChainId, address rollupRecipient) public payable {
        emit Enter(rollupChainId, address(0), rollupRecipient, msg.value);
    }

    /// @notice Allows ERC20s to enter the rollup.
    /// @dev Permanently burns the token amount by locking it in this contract.
    /// @param rollupChainId - The rollup chain to enter.
    /// @param rollupRecipient - The recipient of the Ether on the rollup.
    /// @param token - The address of the ERC20 token on the Host.
    /// @param amount - The amount of the ERC20 token to transfer to the rollup.
    /// @custom:emits Enter indicatig the amount of tokens to mint on the rollup & its recipient.
    function enter(uint256 rollupChainId, address rollupRecipient, address token, uint256 amount) public payable {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        emit Enter(rollupChainId, token, rollupRecipient, amount);
    }

    /// @notice Fulfills exit orders by transferring tokenOut to the recipient
    /// @param orders The exit orders to fulfill
    /// @custom:emits ExitFilled for each exit order fulfilled.
    /// @dev Builder SHOULD call `filfillExits` atomically with `submitBlock`.
    ///      Builder SHOULD set a block expiration time that is AT MOST the minimum of all exit order deadlines;
    ///      this way, `fulfillExits` + `submitBlock` will revert atomically on mainnet if any exit orders have expired.
    ///      Otherwise, `filfillExits` may mine on mainnet, while `submitExit` reverts on the rollup,
    ///      and the Builder can't collect the corresponding value on the rollup.
    /// @dev Called by the Builder atomically with a transaction calling `submitBlock`.
    ///      The user-submitted transactions initiating the ExitOrders on the rollup
    ///      must be included by the Builder in the rollup block submitted via `submitBlock`.
    /// @dev The user transfers tokenIn on the rollup, and receives tokenOut on host.
    /// @dev The Builder receives tokenIn on the rollup, and transfers tokenOut to the user on host.
    /// @dev The rollup STF MUST NOT apply `submitExit` transactions to the rollup state
    ///      UNLESS a corresponding ExitFilled event is emitted on host in the same block.
    /// @dev If the user submits multiple exit transactions for the same token in the same rollup block,
    ///      the Builder may transfer the cumulative tokenOut to the user in a single ExitFilled event.
    ///      The rollup STF will apply the user's exit transactions on the rollup up to the point that sum(tokenOut) is lte the ExitFilled amount.
    /// TODO: add option to fulfill ExitOrders with native ETH? or is it sufficient to only allow users to exit via WETH?
    function fulfillExits(ExitOrder[] calldata orders) external payable {
        uint256 ethRemaining = msg.value;
        for (uint256 i = 0; i < orders.length; i++) {
            // transfer value
            if (orders[i].token == address(0)) {
                // transfer native Ether to the recipient
                payable(orders[i].recipient).transfer(orders[i].amount);
                // NOTE: this will underflow if sender attempts to transfer more Ether than they sent to the contract
                ethRemaining -= orders[i].amount;
            } else {
                // transfer tokens to the recipient
                IERC20(orders[i].token).transferFrom(msg.sender, orders[i].recipient, orders[i].amount);
            }
            // emit
            emit ExitFilled(orders[i].rollupChainId, orders[i].token, orders[i].recipient, orders[i].amount);
        }
    }
}

/// @notice A contract deployed to the Rollup that allows users to atomically exchange tokens on the Rollup for tokens on the Host.
contract RollupPassage {
    /// @notice Thrown when an exit transaction is submitted with a deadline that has passed.
    error OrderExpired();

    /// @notice Emitted when an exit order is submitted & successfully processed, indicating it was also fulfilled on host.
    /// @dev See `submitExit` for parameter docs.
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
    event Sweep(address indexed recipient);

    /// @notice Expresses an intent to exit the rollup with ERC20s.
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
    function submitExit(
        address tokenIn_RU,
        address tokenOut_H,
        address recipient_H,
        uint256 deadline,
        uint256 amountIn_RU,
        uint256 amountOutMinimum_H
    ) external {
        // check that the deadline hasn't passed
        if (block.timestamp >= deadline) revert OrderExpired();

        // transfer the tokens from the user to the contract
        IERC20(tokenIn_RU).transferFrom(msg.sender, address(this), amountIn_RU);

        // emit the exit event
        emit Exit(tokenIn_RU, tokenOut_H, recipient_H, deadline, amountIn_RU, amountOutMinimum_H);
    }

    /// @notice Expresses an intent to exit the rollup with native Ether.
    /// @dev See `submitExit` above for dev details on how exits work.
    /// @dev tokenIn_RU is set to address(0), native rollup Ether.
    ///      amountIn_RU is set to msg.value.
    /// @param tokenOut_H - The address of the token the user expects to receive on host.
    /// @param recipient_H - The address of the recipient of tokenOut_H on host.
    /// @param deadline - The deadline by which the exit order must be fulfilled.
    /// @param amountOutMinimum_H - The minimum amount of tokenOut_H the user expects to receive on host.
    /// @custom:reverts Expired if the deadline has passed.
    /// @custom:emits Exit if the exit transaction succeeds.
    function submitEthExit(address tokenOut_H, address recipient_H, uint256 deadline, uint256 amountOutMinimum_H)
        external
        payable
    {
        // check that the deadline hasn't passed
        if (block.timestamp >= deadline) revert OrderExpired();

        // emit the exit event
        emit Exit(address(0), tokenOut_H, recipient_H, deadline, msg.value, amountOutMinimum_H);
    }

    /// @notice Transfer the entire balance of tokens to the recipient.
    /// @dev Called by the Builder within the same block as `submitExit` transactions to claim the amounts of `tokenIn`.
    /// @dev Builder MUST ensure that no other account calls `sweep` before them.
    /// @param recipient - The address to receive the tokens.
    /// @param tokens - The addresses of the tokens to transfer.
    /// TODO: should there be more granular control for the builder to specify a different recipient for each token?
    function sweep(address recipient, address[] calldata tokens) public {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            token.transfer(recipient, token.balanceOf(address(this)));
        }
        emit Sweep(recipient);
    }

    /// @notice Transfer the entire balance of native Ether to the recipient.
    /// @dev Called by the Builder within the same block as `submitExit` transactions to claim the amounts of native Ether.
    /// @dev Builder MUST ensure that no other account calls `sweepETH` before them.
    /// @param recipient - The address to receive the native Ether.
    function sweepEth(address payable recipient) public {
        recipient.transfer(address(this).balance);
        emit Sweep(recipient);
    }
}
