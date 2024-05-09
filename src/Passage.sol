// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// import IERC20 from OpenZeppelin
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AccessControlDefaultAdminRules} from
    "openzeppelin-contracts/contracts/access/extensions/AccessControlDefaultAdminRules.sol";

abstract contract BasePassage {
    /// @notice Emitted when a swap order is fulfilled by the Builder.
    /// @param originChainId - The chainId of the rollup on which the swap order was initiated.
    /// @param tokenOut - The address of the token transferred to the recipient.
    /// @param recipient - The recipient of the token.
    /// @param amount - The amount of the token transferred to the recipient.
    event SwapFulfilled(
        uint256 indexed originChainId, address indexed tokenOut, address indexed recipient, uint256 amount
    );

    /// @notice Details of an order to be fulfilled by the Builder.
    /// @param tokenOut - The address of the token to be transferred to the recipient.
    ///                   If token is address(0), `amount` is native Ether.
    /// @param recipient - The recipient of the token.
    /// @param amount - The amount of the token to be transferred to the recipient.
    struct SwapFulfillment {
        uint256 originChainId;
        address tokenOut;
        address recipient;
        uint256 amount;
    }

    /// @notice Fulfills exit orders by transferring tokenOut to the recipient
    /// @param orders The exit orders to fulfill
    /// @custom:emits ExitFilled for each exit order fulfilled.
    /// @dev Builder SHOULD call `fulfillExits` atomically with `submitBlock`.
    ///      Builder SHOULD set a block expiration time that is AT MOST the minimum of all exit order deadlines;
    ///      this way, `fulfillExits` + `submitBlock` will revert atomically on mainnet if any exit orders have expired.
    ///      Otherwise, `fulfillExits` may mine on mainnet, while `submitExit` reverts on the rollup,
    ///      and the Builder can't collect the corresponding value on the rollup.
    /// @dev Called by the Builder atomically with a transaction calling `submitBlock`.
    ///      The user-submitted transactions initiating the SwapFulfillments on the rollup
    ///      must be included by the Builder in the rollup block submitted via `submitBlock`.
    /// @dev The user transfers tokenIn on the rollup, and receives tokenOut on host.
    /// @dev The Builder receives tokenIn on the rollup, and transfers tokenOut to the user on host.
    /// @dev The rollup STF MUST NOT apply `submitExit` transactions to the rollup state
    ///      UNLESS a corresponding ExitFilled event is emitted on host in the same block.
    /// @dev If the user submits multiple exit transactions for the same token in the same rollup block,
    ///      the Builder may transfer the cumulative tokenOut to the user in a single ExitFilled event.
    ///      The rollup STF will apply the user's exit transactions on the rollup up to the point that sum(tokenOut) is lte the ExitFilled amount.
    function fulfillSwap(SwapFulfillment[] calldata orders) external payable {
        uint256 ethRemaining = msg.value;
        for (uint256 i = 0; i < orders.length; i++) {
            // transfer value
            if (orders[i].tokenOut == address(0)) {
                // transfer native Ether to the recipient
                payable(orders[i].recipient).transfer(orders[i].amount);
                // NOTE: this will underflow if sender attempts to transfer more Ether than they sent to the contract
                ethRemaining -= orders[i].amount;
            } else {
                // transfer tokens to the recipient
                IERC20(orders[i].tokenOut).transferFrom(msg.sender, orders[i].recipient, orders[i].amount);
            }
            // emit
            emit SwapFulfilled(orders[i].originChainId, orders[i].tokenOut, orders[i].recipient, orders[i].amount);
        }
    }
}

/// @notice A contract deployed to Host chain that allows tokens to enter the rollup,
///         and enables Builders to fulfill requests to exchange tokens on the Rollup for tokens on the Host.
contract Passage is BasePassage, AccessControlDefaultAdminRules {
    /// @notice The chainId of the default rollup chain.
    uint256 immutable defaultRollupChainId;

    /// @notice Emitted when tokens enter the rollup.
    /// @param token - The address of the token entering the rollup.
    /// @param rollupRecipient - The recipient of the token on the rollup.
    /// @param amount - The amount of the token entering the rollup.
    event Enter(uint256 rollupChainId, address indexed token, address indexed rollupRecipient, uint256 amount);

    /// @notice Emitted when the admin withdraws tokens from the contract.
    event Withdraw(Withdrawal withdrawal);

    struct Withdrawal {
        address recipient;
        uint256 ethAmount;
        address[] tokens;
        uint256[] tokenAmounts;
    }

    /// @notice Initializes the Admin role.
    /// @dev See `AccessControlDefaultAdminRules` for information on contract administration.
    ///      - Admin role can grant and revoke Sequencer roles.
    ///      - Admin role can be transferred via two-step process with a 1 day timelock.
    /// @param admin - the address that will be the initial admin.
    constructor(uint256 _defaultRollupChainId, address admin) AccessControlDefaultAdminRules(1 days, admin) {
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
    function enter(uint256 rollupChainId, address rollupRecipient, address token, uint256 amount) public payable {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        emit Enter(rollupChainId, token, rollupRecipient, amount);
    }

    /// @notice Allows the admin to withdraw tokens from the contract.
    /// @dev Only the admin can call this function.
    function withdraw(Withdrawal[] calldata withdrawals) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < withdrawals.length; i++) {
            // transfer ether
            if (withdrawals[i].ethAmount > 0) {
                payable(withdrawals[i].recipient).transfer(withdrawals[i].ethAmount);
            }
            // transfer ERC20 tokens
            for (uint256 j = 0; j < withdrawals[i].tokens.length; j++) {
                IERC20(withdrawals[i].tokens[j]).transfer(withdrawals[i].recipient, withdrawals[i].tokenAmounts[j]);
            }
            emit Withdraw(withdrawals[i]);
        }
    }
}

/// @notice A contract deployed to the Rollup that allows users to atomically exchange tokens on the Rollup for tokens on the Host.
contract RollupPassage is BasePassage {
    /// @notice Thrown when an exit transaction is submitted with a deadline that has passed.
    error OrderExpired();

    /// @notice Emitted when a swap is submitted & successfully processed, indicating it was fulfilled.
    /// @dev if `toHost` is TRUE, Rollup Node must look for `SwapFilled` on the Host chain (emitted by `Passage`).
    ///      if `toHost` is FALSE, Rollup Node must look for `SwapFilled` on the rollup (emitted by this same `RollupPassage`).
    /// @param targetChainId - The chain id the user wants to receive funds on.
    /// @param tokenIn - The address of the token the user supplies as the input on the rollup for the trade.
    /// @param tokenOut - The address of the token the user expects to receive on host.
    /// @param recipient - The address of the recipient of tokenOut_H on host.
    /// @param deadline - The deadline by which the exit order must be fulfilled.
    /// @param amountIn - The amount of tokenIn the user supplies as the input on the rollup for the trade.
    /// @param amountOutMinimum - The minimum amount of tokenOut_H the user expects to receive on host.
    event Swap(
        uint256 indexed targetChainId,
        address indexed tokenIn,
        address tokenOut,
        address indexed recipient,
        uint256 deadline,
        uint256 amountIn,
        uint256 amountOutMinimum
    );

    /// @notice Emitted when tokens or native Ether is swept from the contract.
    /// @dev Intended to improve visibility for Builders to ensure Sweep isn't called unexpectedly.
    ///      Intentionally does not bother to emit which token(s) were swept, nor their amounts.
    event Sweep(address indexed recipient);

    /// @notice Expresses an intent to exit value from the rollup.

    /// @notice TODO
    /// @dev The Rollup STF MUST NOT apply `swap` transactions to the rollup state
    ///      UNLESS a sufficient `SwapFulfilled` event is emitted within the same block on the `targetChain`.
    /// @dev Moving back to the Host chain is modeled as a swap between two tokens.
    ///      `tokenIn` is provided on the rollup; in exchange,
    ///      `tokenOut` is expected to be received on the target chain.
    ///      Users may swap any token pair (homogeneous or heterogeneous)
    ///      between chains (RU to host) or within a chain (RU to same RU).
    /// @dev Any fees paid to the Builders for fulfilling swaps
    ///      can be included within the "exchange rate" between `tokenIn` and `tokenOut`.
    /// @dev The Builder claims `tokenIn` from this contract by calling `sweep` within the same block.
    /// @dev if `tokenIn` or `tokenOut` is set to address(0), this indicates native Ether.
    /// @custom:param See event `Swap` for full param docs.
    /// @custom:reverts `OrderExpired` if the deadline has passed.
    /// @custom:emits `Swap` if the swap transaction mines, which means that the swap was filled.
    function swap(
        uint256 targetChainId,
        address tokenIn,
        address tokenOut,
        address recipient,
        uint256 deadline,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) external payable {
        // check that the deadline hasn't passed
        if (block.timestamp >= deadline) revert OrderExpired();

        // transfer value to this contract
        if (tokenIn == address(0)) {
            // if native ether, ensure value is already attached to the transaction
            require(amountIn == msg.value);
        } else {
            // if ERC20, transfer the token into the contract
            IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        }

        // emit
        emit Swap(targetChainId, tokenIn, tokenOut, recipient, deadline, amountIn, amountOutMinimum);
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
