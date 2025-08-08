// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.26;

// test contracts
import {ZenithTest} from "../local/Zenith.t.sol";

contract ZenithForkTest is ZenithTest {
    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("HOST_RPC_URL"));
        setupStd();
        super.setUp();
    }
}
