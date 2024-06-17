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

    /// @notice Emitted when Ether enters the rollup.
    /// @param rollupRecipient - The recipient of Ether on the rollup.
    /// @param amount - The amount of Ether entering the rollup.
    event Enter(uint256 indexed rollupChainId, address indexed rollupRecipient, uint256 amount);

    /// @notice Emitted to send a special transaction to the rollup.
    event Transact(
        uint256 indexed rollupChainId,
        address indexed sender,
        address indexed to,
        bytes data,
        uint256 value,
        uint256 gas,
        uint256 maxFeePerGas
    );

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
        if (msg.value == 0) return;
        emit Enter(rollupChainId, rollupRecipient, msg.value);
    }

    /// @notice Allows native Ether to enter the default rollup.
    /// @dev see `enter` for docs.
    function enter(address rollupRecipient) external payable {
        enter(defaultRollupChainId, rollupRecipient);
    }

    /// @notice Allows a special transaction to be sent to the rollup with sender == L1 msg.sender.
    /// @dev Transaction is processed after normal rollup block execution.
    /// @dev See `enterTransact` for docs.
    function transact(
        uint256 rollupChainId,
        address to,
        bytes calldata data,
        uint256 value,
        uint256 gas,
        uint256 maxFeePerGas
    ) public payable {
        enterTransact(rollupChainId, msg.sender, to, data, value, gas, maxFeePerGas);
    }

    /// @dev See `transact` for docs.
    function transact(address to, bytes calldata data, uint256 value, uint256 gas, uint256 maxFeePerGas)
        external
        payable
    {
        enterTransact(defaultRollupChainId, msg.sender, to, data, value, gas, maxFeePerGas);
    }

    /// @notice Send Ether on the rollup, send a special transaction to be sent to the rollup with sender == L1 msg.sender.
    /// @dev Enter and Transact are processed after normal rollup block execution.
    /// @dev See `enter` for Enter docs.
    /// @param rollupChainId - The rollup chain to send the transaction to.
    /// @param etherRecipient - The recipient of the ether.
    /// @param to - The address to call on the rollup.
    /// @param data - The data to send to the rollup.
    /// @param value - The amount of Ether to send on the rollup.
    /// @param gas - The gas limit for the transaction.
    /// @param maxFeePerGas - The maximum fee per gas for the transaction (per EIP-1559).
    /// @custom:emits Transact indicating the transaction to mine on the rollup.
    function enterTransact(
        uint256 rollupChainId,
        address etherRecipient,
        address to,
        bytes calldata data,
        uint256 value,
        uint256 gas,
        uint256 maxFeePerGas
    ) public payable {
        // if msg.value is attached, Enter
        enter(rollupChainId, etherRecipient);
        // emit Transact event
        emit Transact(rollupChainId, msg.sender, to, data, value, gas, maxFeePerGas);
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
