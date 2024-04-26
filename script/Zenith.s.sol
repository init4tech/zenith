// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Zenith} from "../src/Zenith.sol";

contract DeployZenith is Script {
    // deploy:
    // forge script DeployZenith --sig "run()" --rpc-url $RPC_URL --etherscan-api-key $ETHERSCAN_API_KEY --private-key $PRIVATE_KEY --broadcast --verify
    function run() public {
        vm.broadcast();
        new Zenith(block.chainid + 1, msg.sender);
    }
}
