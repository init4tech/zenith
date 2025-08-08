// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.26;

// test contracts
import {TransactTest} from "../local/Transactor.t.sol";

contract TransactForkTest is TransactTest {
    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("HOST_RPC_URL"));
        setupStd();
        super.setUp();
    }
}
