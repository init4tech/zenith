// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// utils
import {Test, console2} from "forge-std/Test.sol";

contract GnosisSafeTest is Test {
    function setUp() public {
        vm.createSelectFork("https://ethereum-rpc.publicnode.com");
    }

    // NOTE: this test fails if 4000 gas is provided. seems 4100 is approx the minimum.
    function test_gnosis_receive() public {
        payable(address(0x7c68c42De679ffB0f16216154C996C354cF1161B)).call{value: 1 ether, gas: 4100}("");
    }
}
