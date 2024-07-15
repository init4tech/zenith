// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Zenith} from "../src/Zenith.sol";
import {Passage, RollupPassage} from "../src/Passage.sol";
import {Transactor} from "../src/Transact.sol";
import {HostOrders, RollupOrders} from "../src/Orders.sol";

contract ZenithScript is Script {
    // deploy:
    // forge script ZenithScript --sig "deploy(uint256,address,address)" --rpc-url $RPC_URL --etherscan-api-key $ETHERSCAN_API_KEY --private-key $PRIVATE_KEY --broadcast --verify $ROLLUP_CHAIN_ID $WITHDRAWAL_ADMIN_ADDRESS $INITIAL_ENTER_TOKENS_ARRAY $SEQUENCER_AND_GAS_ADMIN_ADDRESS
    function deploy(
        uint256 defaultRollupChainId,
        address withdrawalAdmin,
        address[] memory initialEnterTokens,
        address sequencerAndGasAdmin
    ) public returns (Zenith z, Passage p, Transactor t, HostOrders m) {
        vm.startBroadcast();
        z = new Zenith(sequencerAndGasAdmin);
        p = new Passage(defaultRollupChainId, withdrawalAdmin, initialEnterTokens);
        t = new Transactor(defaultRollupChainId, sequencerAndGasAdmin, p, 30_000_000, 5_000_000);
        m = new HostOrders();
    }

    // deploy:
    // forge script ZenithScript --sig "deployL2()" --rpc-url $L2_RPC_URL --private-key $PRIVATE_KEY --broadcast
    function deployL2() public returns (RollupPassage p, RollupOrders m) {
        vm.startBroadcast();
        p = new RollupPassage();
        m = new RollupOrders();
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
