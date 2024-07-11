// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {Passage} from "../src/Passage.sol";
import {Transactor} from "../src/Transact.sol";

contract TransactTest is Test {
    Passage public passage;
    Transactor public target;
    uint256 chainId = 3;
    address recipient = address(0x123);
    uint256 amount = 200;

    address to = address(0x01);
    bytes data = abi.encodeWithSelector(Passage.withdraw.selector, address(this), recipient, amount);
    uint256 value = 100;
    uint256 gas = 5_000_000;
    uint256 maxFeePerGas = 50;

    event Transact(
        uint256 indexed rollupChainId,
        address indexed sender,
        address indexed to,
        bytes data,
        uint256 value,
        uint256 gas,
        uint256 maxFeePerGas
    );

    // Passage event
    event Enter(uint256 indexed rollupChainId, address indexed rollupRecipient, uint256 amount);

    function setUp() public {
        // deploy target
        passage = new Passage(block.chainid + 1, address(this), new address[](0));
        target = new Transactor(block.chainid + 1, passage);
    }

    function test_setUp() public {
        assertEq(target.defaultRollupChainId(), block.chainid + 1);
        assertEq(address(target.passage()), address(passage));
    }

    function test_transact() public {
        vm.expectEmit(address(target));
        emit Transact(chainId, address(this), to, data, value, gas, maxFeePerGas);
        target.transact(chainId, to, data, value, gas, maxFeePerGas);

        vm.expectEmit(address(passage));
        emit Enter(chainId, address(this), amount);
        target.transact{value: amount}(chainId, to, data, value, gas, maxFeePerGas);
    }

    function test_transact_defaultChain() public {
        vm.expectEmit(address(target));
        emit Transact(target.defaultRollupChainId(), address(this), to, data, value, gas, maxFeePerGas);
        target.transact(to, data, value, gas, maxFeePerGas);

        vm.expectEmit(address(passage));
        emit Enter(target.defaultRollupChainId(), address(this), amount);
        target.transact{value: amount}(to, data, value, gas, maxFeePerGas);
    }

    function test_enterTransact() public {
        vm.expectEmit(address(target));
        emit Transact(chainId, address(this), to, data, value, gas, maxFeePerGas);
        target.enterTransact(chainId, recipient, to, data, value, gas, maxFeePerGas);

        vm.expectEmit(address(passage));
        emit Enter(chainId, recipient, amount);
        target.enterTransact{value: amount}(chainId, recipient, to, data, value, gas, maxFeePerGas);
    }

    function test_transact_perTransactGasLimit() public {
        // attempt transact with 5M + 1 gas.
        vm.expectRevert(Transactor.PerTransactGasLimit.selector);
        target.transact(chainId, to, data, value, gas + 1, maxFeePerGas);
    }

    function test_transact_globalGasLimit() public {
        // submit 6x transacts with 5M gas, consuming the total 30M global limit
        for (uint256 i; i < 6; i++) {
            target.transact(to, data, value, gas, maxFeePerGas);
        }

        // attempt to submit another transact with 1 gas - should revert.
        vm.expectRevert(abi.encodeWithSelector(Transactor.PerBlockTransactGasLimit.selector));
        target.transact(to, data, value, 1, maxFeePerGas);
    }
}
