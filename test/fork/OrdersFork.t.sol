// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.26;

// test contracts
import {OrdersTest} from "../local/Orders.t.sol";

contract OrdersForkTest is OrdersTest {
    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("RU_RPC_URL"));
        setupStd();
        super.setUp();
    }
}
