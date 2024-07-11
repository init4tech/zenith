// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20Burnable} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/// @notice A contract deployed to Host chain that allows tokens to enter the rollup.
contract Passage {
    /// @notice The chainId of rollup that Ether will be sent to by default when entering the rollup via fallback() or receive().
    uint256 public immutable defaultRollupChainId;

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
    event Enter(uint256 indexed rollupChainId, address indexed rollupRecipient, uint256 amount);

    /// @notice Emitted when ERC20 tokens enter the rollup.
    /// @param rollupChainId - The chainId of the destination rollup.
    /// @param rollupRecipient - The recipient of tokens on the rollup.
    /// @param token - The host chain address of the token entering the rollup.
    /// @param amount - The amount of tokens entering the rollup.
    event EnterToken(
        uint256 indexed rollupChainId, address indexed rollupRecipient, address indexed token, uint256 amount
    );

    /// @notice Emitted when the admin withdraws tokens from the contract.
    event Withdrawal(address indexed token, address indexed recipient, uint256 amount);

    /// @notice Emitted when the admin allow/disallow ERC20 Enters for a given token.
    event EnterConfigured(address indexed token, bool indexed canEnter);

    /// @param _defaultRollupChainId - the chainId of the rollup that Ether will be sent to by default
    ///                                when entering the rollup via fallback() or receive() fns.
    constructor(uint256 _defaultRollupChainId, address _tokenAdmin, address[] memory initialEnterTokens) {
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
    function enter(uint256 rollupChainId, address rollupRecipient) public payable {
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
    function enterToken(uint256 rollupChainId, address rollupRecipient, address token, uint256 amount) public {
        if (!canEnter[token]) revert DisallowedEnter(token);
        if (amount == 0) return;
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        emit EnterToken(rollupChainId, rollupRecipient, token, amount);
    }

    /// @notice Allows ERC20 tokens to enter the default rollup.
    /// @dev see `enterToken` for docs.
    function enterToken(address rollupRecipient, address token, uint256 amount) external {
        enterToken(defaultRollupChainId, rollupRecipient, token, amount);
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

    /// @notice Helper to configure ERC20 enters on deploy & via admin function
    function _configureEnter(address token, bool _canEnter) internal {
        canEnter[token] = _canEnter;
        emit EnterConfigured(token, _canEnter);
    }
}

/// @notice Enables tokens to Exit the rollup.
contract RollupPassage {
    /// @notice Emitted when native Ether exits the rollup.
    /// @param hostRecipient - The *requested* recipient of tokens on the host chain.
    /// @param amount - The amount of Ether exiting the rollup.
    event Exit(address indexed hostRecipient, uint256 amount);

    /// @notice Emitted when ERC20 tokens exit the rollup.
    /// @param hostRecipient - The *requested* recipient of tokens on the host chain.
    /// @param token - The token exiting the rollup.
    /// @param amount - The amount of ERC20s exiting the rollup.
    event ExitToken(address indexed hostRecipient, address indexed token, uint256 amount);

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
    function exitToken(address hostRecipient, address token, uint256 amount) public {
        if (amount == 0) return;
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        ERC20Burnable(token).burn(amount);
        emit ExitToken(hostRecipient, token, amount);
    }
}
