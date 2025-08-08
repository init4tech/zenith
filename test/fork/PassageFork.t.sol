// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.26;

// test contracts
import {PassageTest, RollupPassageTest} from "../local/Passage.t.sol";

contract PassageForkTest is PassageTest {
    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("HOST_RPC_URL"));
        setupStd();
        super.setUp();
    }
}

contract RollupPassageForkTest is RollupPassageTest {
    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("RU_RPC_URL"));
        setupStd();
        super.setUp();
    }
}
