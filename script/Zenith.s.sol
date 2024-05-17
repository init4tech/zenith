// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Zenith} from "../src/Zenith.sol";

contract ZenithScript is Script {
    // deploy:
    // forge script ZenithScript --sig "deploy(uint256,address,address)" --rpc-url $RPC_URL --etherscan-api-key $ETHERSCAN_API_KEY --private-key $PRIVATE_KEY --broadcast --verify $ROLLUP_CHAIN_ID $WITHDRAWAL_ADMIN_ADDRESS $SEQUENCER_ADMIN_ADDRESS
    function deploy(uint256 defaultRollupChainId, address withdrawalAdmin, address sequencerAdmin)
        public
        returns (Zenith z)
    {
        vm.startBroadcast();
        z = new Zenith(defaultRollupChainId, withdrawalAdmin, sequencerAdmin);
        // send some ETH to newly deployed Zenith to populate some rollup state
        payable(address(z)).transfer(0.00123 ether);
    }

    // NOTE: script must be run using SequencerAdmin key
    // set sequencer:
    // forge script ZenithScript --sig "setSequencerRole(address,address)" --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast $ZENITH_ADDRESS $SEQUENCER_ADDRESS
    function setSequencerRole(address payable z, address sequencer) public {
        vm.startBroadcast();
        Zenith zenith = Zenith(z);
        zenith.addSequencer(sequencer);
    }

    // NOTE: script must be run using SequencerAdmin key
    // revoke sequencer:
    // forge script ZenithScript --sig "revokeSequencerRole(address,address)" --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast $ZENITH_ADDRESS $SEQUENCER_ADDRESS
    function revokeSequencerRole(address payable z, address sequencer) public {
        vm.startBroadcast();
        Zenith zenith = Zenith(z);
        zenith.removeSequencer(sequencer);
    }
}
