// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {Zenith} from "../src/Zenith.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract TestERC20 is ERC20Burnable {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }
}

contract HelpersTest is Test {
    Zenith public target;

    function setUp() public {
        vm.createSelectFork("https://rpc.holesky.ethpandaops.io");
        target = new Zenith(0x29403F107781ea45Bf93710abf8df13F67f2008f);
    }

    function check_signature() public {
        bytes32 hash = 0xdcd0af9a45fa82dcdd1e4f9ef703d8cd459b6950c0638154c67117e86facf9c1;
        uint8 v = 28;
        bytes32 r = 0xb89764d107f812dbbebb925711b320d336ff8d03f08570f051123df86334f3f5;
        bytes32 s = 0x394cd592577ce6307154045607b9b18ecc1de0eb636e996981477c2d9b1a7675;
        address signer = ecrecover(hash, v, r, s);
        vm.label(signer, "recovered signer");
        assertEq(signer, 0x5b0517Dc94c413a5871536872605522E54C85a03);
    }
}
