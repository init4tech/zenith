// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Zenith} from "../src/Zenith.sol";

contract DeployZenith is Script {
    // deploy:
    // forge script DeployZenith --sig "run(address)" --rpc-url $RPC_URL --etherscan-api-key $ETHERSCAN_API_KEY --private-key $PRIVATE_KEY --broadcast --verify $SEQUENCER_KEY
    function run(address sequencer) public {
        vm.startBroadcast();
        Zenith z = new Zenith(block.chainid + 1, msg.sender);
        z.grantRole(z.SEQUENCER_ROLE(), sequencer);
        payable(address(z)).send(0.0123 ether);
    }
}
