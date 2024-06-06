// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @notice A contract deployed to Host chain that allows tokens to enter the rollup,
///         and enables Builders to fulfill requests to exchange tokens on the Rollup for tokens on the Host.
contract Passage {
    /// @notice The chainId of rollup that Ether will be sent to by default when entering the rollup via fallback() or receive().
    uint256 public immutable defaultRollupChainId;

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
    /// @param rollupChainId - The rollup chain to enter.
    /// @param rollupRecipient - The recipient of the Ether on the rollup.
    /// @custom:emits Enter indicating the amount of Ether to mint on the rollup & its recipient.
    function enter(uint256 rollupChainId, address rollupRecipient) public payable {
        emit Enter(rollupChainId, address(0), rollupRecipient, msg.value);
    }

    /// @notice Allows ERC20s to enter the rollup.
    /// @param rollupChainId - The rollup chain to enter.
    /// @param rollupRecipient - The recipient of the Ether on the rollup.
    /// @param token - The address of the ERC20 token on the Host.
    /// @param amount - The amount of the ERC20 token to transfer to the rollup.
    /// @custom:emits Enter indicating the amount of tokens to mint on the rollup & its recipient.
    function enter(uint256 rollupChainId, address token, address rollupRecipient, uint256 amount) external payable {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        emit Enter(rollupChainId, token, rollupRecipient, amount);
    }

    /// @notice Allows the admin to withdraw ETH or ERC20 tokens from the contract.
    /// @dev Only the admin can call this function.
    function withdraw(address token, address recipient, uint256 amount) external {
        if (msg.sender != withdrawalAdmin) revert OnlyWithdrawalAdmin();
        if (token == address(0)) {
            payable(recipient).transfer(amount);
        } else {
            IERC20(token).transfer(recipient, amount);
        }
        emit Withdrawal(token, recipient, amount);
    }
}

/// @notice A contract deployed to the Rollup that allows users to remove tokens from the Rollup TVL back to the Host.
contract RollupPassage {
    address public immutable hostPassage;

    /// @notice Thrown when attempting to mint ERC20s if not the host passage contract.
    error OnlyHostPassage();

    /// @notice Emitted when tokens exit the rollup.
    /// @param token - The address of the token exiting the rollup.
    /// @param recipient - The desired recipient of the token on the host chain.
    /// @param amount - The amount of the token entering the rollup.
    event Exit(address indexed token, address indexed recipient, uint256 amount);

    /// @notice Emitted when ERC20 tokens are minted on the rollup.
    /// @param token - The address of the ERC20 token entering the rollup.
    /// @param rollupRecipient - The recipient of the ERC20 token on the rollup.
    /// @param amount - The amount of the ERC20 token entering the rollup.
    event Enter(address indexed token, address indexed rollupRecipient, uint256 amount);

    constructor(address _hostPassage) {
        hostPassage = _hostPassage;
    }

    /// @notice Allows ERC20s to enter the rollup from L1.
    /// @param token - The address of the L1 ERC20 token to mint a representation for.
    /// @param rollupRecipient - The recipient of the ERC20 tokens on the rollup, specified by the sender on L1.
    /// @param amount - The amount of the ERC20 token to mint on the Rollup, corresponding to the amount locked on L1.
    /// @custom:emits Exit indicating the the desired recipient on the host chain.
    function enter(address token, address rollupRecipient, uint256 amount) external {
        // TODO: important that no code is deployed to hostPassage address on the rollup :think:
        if (msg.sender != hostPassage) revert OnlyHostPassage();
        // TODO: IERC20(token).mint(recipient, amount);
        emit Enter(token, rollupRecipient, amount);
    }

    /// @notice Allows native Ether to exit the rollup.
    /// @dev Rollup node will burn the msg.value.
    /// @param recipient - The desired recipient of the Ether on the host chain.
    /// @custom:emits Exit indicating the amount of Ether to burn on the rollup & the recipient on the host chain.
    function exit(address recipient) public payable {
        emit Exit(address(0), recipient, msg.value);
    }

    /// @notice Allows ERC20s to exit the rollup.
    /// @param recipient - The desired recipient of the ERC20s on the host chain.
    /// @param token - The address of the ERC20 token on the Rollup.
    /// @param amount - The amount of the ERC20 token to burn on the Rollup.
    /// @custom:emits Exit indicating the the desired recipient on the host chain.
    function exit(address token, address recipient, uint256 amount) external payable {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        // TODO: IERC20(token).burn(msg.sender, amount);
        emit Exit(token, recipient, amount);
    }
}
