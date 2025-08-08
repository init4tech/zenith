// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.26;

// test contracts
import {PassagePermit2Test, RollupPassagePermit2Test} from "../local/Permit2Passage.t.sol";

contract PassagePermit2ForkTest is PassagePermit2Test {
    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("HOST_RPC_URL"));
        setupStd();
        super.setUp();
    }
}

contract RollupPassagePermit2ForkTest is RollupPassagePermit2Test {
    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("RU_RPC_URL"));
        setupStd();
        super.setUp();
    }
}
