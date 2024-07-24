// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {PassagePermit2} from "./PassagePermit2.sol";
import {UsesPermit2} from "../UsesPermit2.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @notice A contract deployed to Host chain that allows tokens to enter the rollup.
contract Passage is PassagePermit2 {
    /// @notice The chainId of rollup that Ether will be sent to by default when entering the rollup via fallback() or receive().
    uint64 public immutable defaultRollupChainId;

    /// @notice The address that is allowed to withdraw funds from the contract.
    address public immutable tokenAdmin;

    /// @notice tokenAddress => whether new EnterToken events are currently allowed for that token.
    mapping(address => bool) public canEnter;

    /// @notice Thrown when attempting to call admin functions if not the token admin.
    error OnlyTokenAdmin();

    /// @notice Thrown when attempting to enter the rollup with an ERC20 token that is not currently allowed.
    error DisallowedEnter(address token);

    /// @notice Emitted when Ether enters the rollup.
    /// @param rollupChainId - The chainId of the destination rollup.
    /// @param rollupRecipient - The recipient of Ether on the rollup.
    /// @param amount - The amount of Ether entering the rollup.
    event Enter(uint64 indexed rollupChainId, address indexed rollupRecipient, uint256 amount);

    /// @notice Emitted when ERC20 tokens enter the rollup.
    /// @param rollupChainId - The chainId of the destination rollup.
    /// @param rollupRecipient - The recipient of tokens on the rollup.
    /// @param token - The host chain address of the token entering the rollup.
    /// @param amount - The amount of tokens entering the rollup.
    event EnterToken(
        uint64 indexed rollupChainId, address indexed rollupRecipient, address indexed token, uint256 amount
    );

    /// @notice Emitted when the admin withdraws tokens from the contract.
    event Withdrawal(address indexed token, address indexed recipient, uint256 amount);

    /// @notice Emitted when the admin allow/disallow ERC20 Enters for a given token.
    event EnterConfigured(address indexed token, bool indexed canEnter);

    /// @param _defaultRollupChainId - the chainId of the rollup that Ether will be sent to by default
    ///                                when entering the rollup via fallback() or receive() fns.
    constructor(
        uint64 _defaultRollupChainId,
        address _tokenAdmin,
        address[] memory initialEnterTokens,
        address _permit2
    ) UsesPermit2(_permit2) {
        defaultRollupChainId = _defaultRollupChainId;
        tokenAdmin = _tokenAdmin;
        for (uint256 i; i < initialEnterTokens.length; i++) {
            _configureEnter(initialEnterTokens[i], true);
        }
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
    /// @param rollupChainId - The rollup chain to enter.
    /// @param rollupRecipient - The recipient of the Ether on the rollup.
    /// @custom:emits Enter indicating the amount of Ether to mint on the rollup & its recipient.
    function enter(uint64 rollupChainId, address rollupRecipient) public payable {
        if (msg.value == 0) return;
        emit Enter(rollupChainId, rollupRecipient, msg.value);
    }

    /// @notice Allows native Ether to enter the default rollup.
    /// @dev see `enter` for docs.
    function enter(address rollupRecipient) external payable {
        enter(defaultRollupChainId, rollupRecipient);
    }

    /// @notice Allows ERC20 tokens to enter the rollup.
    /// @param rollupChainId - The rollup chain to enter.
    /// @param rollupRecipient - The recipient of tokens on the rollup.
    /// @param token - The host chain address of the token entering the rollup.
    /// @param amount - The amount of tokens entering the rollup.
    function enterToken(uint64 rollupChainId, address rollupRecipient, address token, uint256 amount) public {
        // transfer tokens to this contract
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        // check and emit
        _enterToken(rollupChainId, rollupRecipient, token, amount);
    }

    /// @notice Allows ERC20 tokens to enter the default rollup.
    /// @dev see `enterToken` for docs.
    function enterToken(address rollupRecipient, address token, uint256 amount) external {
        enterToken(defaultRollupChainId, rollupRecipient, token, amount);
    }

    /// @notice Allows ERC20 tokens to enter the rollup.
    /// @param rollupChainId - The rollup chain to enter.
    /// @param rollupRecipient - The recipient of tokens on the rollup.
    /// @param permit2 - The Permit2 information, including token & amount.
    function enterTokenPermit2(uint64 rollupChainId, address rollupRecipient, PassagePermit2.Permit2 calldata permit2)
        external
    {
        // transfer tokens to this contract via permit2
        _permitWitnessTransferFrom(enterWitness(rollupChainId, rollupRecipient), permit2);
        // check and emit
        _enterToken(rollupChainId, rollupRecipient, permit2.permit.permitted.token, permit2.permit.permitted.amount);
    }

    /// @notice Alow/Disallow a given ERC20 token to enter the rollup.
    function configureEnter(address token, bool _canEnter) external {
        if (msg.sender != tokenAdmin) revert OnlyTokenAdmin();
        if (canEnter[token] != _canEnter) _configureEnter(token, _canEnter);
    }

    /// @notice Allows the admin to withdraw ETH or ERC20 tokens from the contract.
    /// @dev Only the admin can call this function.
    function withdraw(address token, address recipient, uint256 amount) external {
        if (msg.sender != tokenAdmin) revert OnlyTokenAdmin();
        if (token == address(0)) {
            payable(recipient).transfer(amount);
        } else {
            IERC20(token).transfer(recipient, amount);
        }
        emit Withdrawal(token, recipient, amount);
    }

    /// @notice Shared functionality for tokens entering rollup.
    function _enterToken(uint64 rollupChainId, address rollupRecipient, address token, uint256 amount) internal {
        if (amount == 0) return;
        if (!canEnter[token]) revert DisallowedEnter(token);
        emit EnterToken(rollupChainId, rollupRecipient, token, amount);
    }

    /// @notice Helper to configure ERC20 enters on deploy & via admin function
    function _configureEnter(address token, bool _canEnter) internal {
        canEnter[token] = _canEnter;
        emit EnterConfigured(token, _canEnter);
    }
}
