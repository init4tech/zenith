// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.26;

// system contracts
import {RollupOrders} from "../src/orders/RollupOrders.sol";
import {RollupPassage} from "../src/passage/RollupPassage.sol";
// simple erc20
import {SimpleERC20} from "simple-erc20/SimpleERC20.sol";
// utils
import {Script, console2} from "forge-std/Script.sol";

// create2 address for Permit2
address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
// address that can mint ERC20 tokens. equal to "tokenadmin" in hex.
// the Signet Node makes evm executions from this address to perform ERC20 bridge-ins.
address constant MINTER = 0x00000000000000000000746f6b656E61646d696E;

contract L2Script is Script {
    // deploy:
    // forge script L2Script --sig "deploySystem()" --rpc-url $RPC_URL --broadcast [signing args]
    function deploySystem() public returns (address rollupPassage, address rollupOrders, address wbtc, address usdt) {
        vm.startBroadcast();

        // deploy system contracts
        rollupPassage = address(new RollupPassage{salt: "zenith.rollupPassage"}(PERMIT2));
        rollupOrders = address(new RollupOrders{salt: "zenith.rollupOrders"}(PERMIT2));

        // deploy simple erc20 tokens
        wbtc = address(new SimpleERC20{salt: "zenith.wbtc"}(MINTER, "Wrapped BTC", "WBTC", 8));
        usdt = address(new SimpleERC20{salt: "zenith.usdt"}(MINTER, "Tether USD", "USDT", 6));
    }
}

// NOTE: must deploy Permit2 via https://github.com/Uniswap/permit2/blob/main/script/DeployPermit2.s.sol
// in order to properly setup _CACHED_CHAIN_ID and _CACHED_DOMAIN_SEPARATOR

// NOTE: must deploy USDC via https://github.com/circlefin/stablecoin-evm/blob/master/scripts/deploy/deploy-fiat-token.s.sol
