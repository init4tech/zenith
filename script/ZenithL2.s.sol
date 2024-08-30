// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.26;

// system contracts
import {deployPartOne, deployPartTwo} from "./DeployL2.s.sol";
// utils
import {Script, console2} from "forge-std/Script.sol";

contract L2Script is Script {
    // deploy:
    // forge script L2Script --sig "deployOne()" --fork-url $ANVIL_URL --broadcast
    function deployOne() public returns (address rollupPassage, address rollupOrders, address wbtc, address usdt) {
        vm.startBroadcast();
        (rollupPassage, rollupOrders, wbtc, usdt) = deployPartOne();
    }

    // deploy:
    // forge script L2Script --sig "deployTwo()" --fork-url $ANVIL_URL --broadcast
    function deployTwo()
        public
        returns (address gnosisFactory, address gnosisSingleton, address gnosisFallbackHandler, address usdcAdmin)
    {
        vm.startBroadcast();
        (gnosisFactory, gnosisSingleton, gnosisFallbackHandler, usdcAdmin) = deployPartTwo();
    }
}
