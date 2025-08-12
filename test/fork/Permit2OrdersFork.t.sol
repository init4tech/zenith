// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.26;

// test contracts
import {OrderOriginPermit2Test} from "../local/Permit2Orders.t.sol";

contract Permit2OrdersForkTest is OrderOriginPermit2Test {
    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("RU_RPC_URL"));
        setupStd();
        super.setUp();
    }
}
