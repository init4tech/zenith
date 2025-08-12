// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {RollupOrders} from "../src/orders/RollupOrders.sol";
import {RollupPassage} from "../src/passage/RollupPassage.sol";
import {Zenith} from "../src/Zenith.sol";
import {Transactor} from "../src/Transactor.sol";
import {HostOrders} from "../src/orders/HostOrders.sol";
import {Passage} from "../src/passage/Passage.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title PecorinoConstants
/// @author init4
/// @notice Constants for the Pecorino testnet.
/// @dev These constants are used to configure the SignetStd contract in its
///      constructor, if the chain ID matches the Pecorino testnet chain ID.
library PecorinoConstants {
    /// @notice The Pecorino Rollup chain ID.
    uint32 constant ROLLUP_CHAIN_ID = 14174;
    /// @notice The Rollup Passage contract for the Pecorino testnet.
    RollupPassage constant ROLLUP_PASSAGE = RollupPassage(payable(0x0000000000007369676E65742D70617373616765));
    /// @notice The Rollup Orders contract for the Pecorino testnet.
    RollupOrders constant ROLLUP_ORDERS = RollupOrders(0x000000000000007369676E65742D6f7264657273);
    /// @notice WETH token address for the Pecorino testnet.
    IERC20 constant ROLLUP_WETH = IERC20(0x0000000000000000007369676e65742d77657468);
    /// @notice WBTC token address for the Pecorino testnet.
    IERC20 constant ROLLUP_WBTC = IERC20(0x0000000000000000007369676e65742D77627463);
    /// @notice WUSD token address for the Pecorino testnet.
    IERC20 constant ROLLUP_WUSD = IERC20(0x0000000000000000007369676e65742D77757364);

    /// @notice The Pecorino host chain ID.
    uint32 constant HOST_CHAIN_ID = 3151908;
    /// @notice The Passage contract on the host network.
    Passage constant HOST_PASSAGE = Passage(payable(0x12585352AA1057443D6163B539EfD4487f023182));
    /// @notice The Orders contract on the host network.
    HostOrders constant HOST_ORDERS = HostOrders(0x0A4f505364De0Aa46c66b15aBae44eBa12ab0380);
    /// @notice The Zenith contract for the Pecorino testnet.
    Zenith constant HOST_ZENITH = Zenith(0xf17E98baF73F7C78a42D73DF4064de5B7A20EcA6);
    /// @notice The Transactor contract on the host network.
    Transactor constant HOST_TRANSACTOR = Transactor(0x3903279B59D3F5194053dA8d1f0C7081C8892Ce4);
    /// @notice USDC token for the Pecorino testnet host chain.
    IERC20 constant HOST_USDC = IERC20(0x65Fb255585458De1F9A246b476aa8d5C5516F6fd);
    /// @notice USDT token for the Pecorino testnet host chain.
    IERC20 constant HOST_USDT = IERC20(0xb9Df1b911B6cf6935b2a918Ba03dF2372E94e267);
    /// @notice WBTC token for the Pecorino testnet host chain.
    IERC20 constant HOST_WBTC = IERC20(0xfb29F7d7a4CE607D6038d44150315e5F69BEa08A);
    /// @notice WETH token for the Pecorino testnet host chain.
    IERC20 constant HOST_WETH = IERC20(0xd03d085B78067A18155d3B29D64914df3D19A53C);

    /// @notice The token admin address, used for configuring tokens on Passage and for withdrawals.
    address constant TOKEN_ADMIN = address(0x11Aa4EBFbf7a481617c719a2Df028c9DA1a219aa);
    /// @notice The gas admin address, used for configuring gas limits on Transactor.
    address constant GAS_ADMIN = address(0x29403F107781ea45Bf93710abf8df13F67f2008f);
    /// @notice The sequencer admin address, used for configuring sequencer settings on Zenith.
    address constant SEQUENCER_ADMIN = address(0x29403F107781ea45Bf93710abf8df13F67f2008f);
}

contract SignetStd {
    /// SHARED CONSTANTS
    /// @notice The native asset address, used as a sentinel for native USD on
    ///         the rollup, or native ETH on the host.
    address constant NATIVE_ASSET = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    /// @notice Permit2 contract address, which is the same on all chains.
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    /// ROLLUP CONSTANTS
    /// @notice The chain ID of the rollup.
    uint32 internal ROLLUP_CHAIN_ID;
    /// @notice The Rollup Passage contract.
    RollupPassage internal ROLLUP_PASSAGE;
    /// @notice The Rollup Orders contract.
    RollupOrders internal ROLLUP_ORDERS;
    /// @notice The WETH token address.
    IERC20 internal ROLLUP_WETH;
    /// @notice The WBTC token address.
    IERC20 internal ROLLUP_WBTC;
    /// @notice The WUSD token address.
    IERC20 internal ROLLUP_WUSD;
    /// @notice The system address that mints tokens on the rollup.
    address internal ROLLUP_MINTER = address(0x00000000000000000000746f6b656E61646d696E);

    /// HOST CONSTANTS
    /// @notice The chain ID of the host network.
    uint32 internal HOST_CHAIN_ID;
    /// @notice The Passage contract on the host network.
    Passage internal HOST_PASSAGE;
    /// @notice The Orders contract on the host network.
    HostOrders internal HOST_ORDERS;
    /// @notice The Zenith contract.
    Zenith internal HOST_ZENITH;
    /// @notice The Transact contract on the host network.
    Transactor internal HOST_TRANSACTOR;
    /// @notice The USDC token address on the host network.
    IERC20 internal HOST_USDC;
    /// @notice The USDT token address on the host network.
    IERC20 internal HOST_USDT;
    /// @notice The WBTC token address on the host network.
    IERC20 internal HOST_WBTC;
    /// @notice The WETH token address on the host network.
    IERC20 internal HOST_WETH;
    /// @notice The token admin address, used for configuring tokens on Passage and for withdrawals.
    address internal TOKEN_ADMIN;
    /// @notice The gas admin address, used for configuring gas limits on Transactor.
    address internal GAS_ADMIN;
    /// @notice The sequencer admin address, used for configuring sequencer settings on Zenith.
    address internal SEQUENCER_ADMIN;

    constructor() {
        setupStd();
    }

    function setupStd() internal virtual {
        // Auto-configure based on the chain ID.
        if (block.chainid == PecorinoConstants.ROLLUP_CHAIN_ID || block.chainid == PecorinoConstants.HOST_CHAIN_ID) {
            ROLLUP_CHAIN_ID = PecorinoConstants.ROLLUP_CHAIN_ID;
            ROLLUP_PASSAGE = PecorinoConstants.ROLLUP_PASSAGE;
            ROLLUP_ORDERS = PecorinoConstants.ROLLUP_ORDERS;
            ROLLUP_WETH = PecorinoConstants.ROLLUP_WETH;
            ROLLUP_WBTC = PecorinoConstants.ROLLUP_WBTC;
            ROLLUP_WUSD = PecorinoConstants.ROLLUP_WUSD;

            HOST_CHAIN_ID = PecorinoConstants.HOST_CHAIN_ID;
            HOST_PASSAGE = PecorinoConstants.HOST_PASSAGE;
            HOST_ORDERS = PecorinoConstants.HOST_ORDERS;
            HOST_ZENITH = PecorinoConstants.HOST_ZENITH;
            HOST_TRANSACTOR = PecorinoConstants.HOST_TRANSACTOR;
            HOST_USDC = PecorinoConstants.HOST_USDC;
            HOST_USDT = PecorinoConstants.HOST_USDT;
            HOST_WBTC = PecorinoConstants.HOST_WBTC;
            HOST_WETH = PecorinoConstants.HOST_WETH;
            TOKEN_ADMIN = PecorinoConstants.TOKEN_ADMIN;
            GAS_ADMIN = PecorinoConstants.GAS_ADMIN;
            SEQUENCER_ADMIN = PecorinoConstants.SEQUENCER_ADMIN;
        } else {
            revert("Unsupported chain ID");
        }
    }
}
