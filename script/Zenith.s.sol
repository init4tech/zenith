// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.26;

// deploy contracts
import {Zenith} from "../src/Zenith.sol";
import {Transactor} from "../src/Transactor.sol";
import {HostOrders} from "../src/orders/HostOrders.sol";
import {Passage} from "../src/passage/Passage.sol";
// utils
import {Script} from "forge-std/Script.sol";

contract ZenithScript is Script {
    // deploy:
    // forge script ZenithScript --sig "deploy(uint256,address,address,address,address[],address,uint256,uint256)" --rpc-url $RPC_URL --broadcast $ROLLUP_CHAIN_ID $SEQUENCER_ADMIN_ADDRESS $WITHDRAWAL_ADMIN_ADDRESS $GAS_ADMIN_ADDRESS $INITIAL_ENTER_TOKENS_ARRAY $PERMIT2_ADDRESS $PER_BLOCK_GAS_LIMIT $PER_TRANSACT_GAS_LIMIT [signing args] [--etherscan-api-key $ETHERSCAN_API_KEY --verify]
    function deploy(
        uint256 defaultRollupChainId,
        address sequencerAdmin,
        address withdrawalAdmin,
        address gasAdmin,
        address[] memory initialEnterTokens,
        address permit2,
        uint256 perBlockGasLimit,
        uint256 perTransactGasLimit
    ) public returns (Zenith z, Passage p, Transactor t, HostOrders m) {
        vm.startBroadcast();
        z = new Zenith{salt: "zenith.zenith "}(sequencerAdmin);
        p = new Passage{salt: "zenith.passage "}(defaultRollupChainId, withdrawalAdmin, initialEnterTokens, permit2);
        t = new Transactor{salt: "zenith.transactor "}(
            defaultRollupChainId, gasAdmin, p, perBlockGasLimit, perTransactGasLimit
        );
        m = new HostOrders{salt: "zenith.hostOrders "}(permit2);
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
