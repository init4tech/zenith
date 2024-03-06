// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Zenith} from "../src/Zenith.sol";

contract DeployZenith is Script {
    // deploy: forge script DeployZenith --sig "run()" --rpc-url $RPC --etherscan-api-key $ETHERSCAN_API_KEY --private-key $RAW_PRIVATE_KEY --broadcast --verify

    // deploy NO VERIFY: forge script DeployZenith --sig "run()" --rpc-url $RPC --private-key $RAW_PRIVATE_KEY --broadcast
    function run() public {
        vm.broadcast();
        new Zenith{salt: "zenith"}();
    }
}
