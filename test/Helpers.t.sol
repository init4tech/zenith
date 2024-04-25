// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {Zenith} from "../src/Zenith.sol";

contract HelpersTest is Test {
    Zenith public target;

    function setUp() public {
        vm.createSelectFork("https://rpc.holesky.ethpandaops.io");
        target = new Zenith(block.chainid + 1, 0x0a53e650c6f015eF70a15Da7B18fa95F051465aB);
    }

    function test_signature() public {
        bytes32 hash = 0xdcd0af9a45fa82dcdd1e4f9ef703d8cd459b6950c0638154c67117e86facf9c1;
        uint8 v = 28;
        bytes32 r = 0xb89764d107f812dbbebb925711b320d336ff8d03f08570f051123df86334f3f5;
        bytes32 s = 0x394cd592577ce6307154045607b9b18ecc1de0eb636e996981477c2d9b1a7675;
        address signer = ecrecover(hash, v, r, s);
        vm.label(signer, "recovered signer");
        assertEq(signer, 0x5b0517Dc94c413a5871536872605522E54C85a03);
    }
}
