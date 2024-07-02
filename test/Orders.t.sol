// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {RollupOrders, Input, Output, OrderOrigin} from "../src/Orders.sol";
import {TestERC20} from "./Helpers.t.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract OrdersTest is Test {
    RollupOrders public target;
    Input[] public inputs;
    Output[] public outputs;

    mapping(address => bool) isToken;

    address token;
    uint32 chainId = 3;
    address recipient = address(0x123);
    uint256 amount = 200;
    uint256 deadline = block.timestamp;

    event OutputFilled(uint256 indexed originChainId, address indexed recipient, address indexed token, uint256 amount);

    event Order(uint256 deadline, Input[] inputs, Output[] outputs);

    event Sweep(address indexed recipient, address indexed token, uint256 amount);

    function setUp() public {
        target = new RollupOrders();

        // setup token
        token = address(new TestERC20("hi", "HI"));
        TestERC20(token).mint(address(this), amount * 10000);
        TestERC20(token).approve(address(target), amount * 10000);
        isToken[token] = true;

        // setup Order Inputs/Outputs
        Input memory input = Input(token, amount);
        inputs.push(input);

        Output memory output = Output(token, amount, recipient, chainId);
        outputs.push(output);
    }

    // input ERC20
    function test_initiate_ERC20() public {
        // expect Order event is initiated, ERC20 is transferred
        vm.expectEmit();
        emit Order(deadline, inputs, outputs);
        vm.expectCall(
            token, abi.encodeWithSelector(ERC20.transferFrom.selector, address(this), address(target), amount)
        );
        target.initiate(deadline, inputs, outputs);
    }

    // input ETH
    function test_initiate_ETH() public {
        // change input to ETH
        inputs[0].token = address(0);

        // expect Order event is initiated
        vm.expectEmit();
        emit Order(deadline, inputs, outputs);
        target.initiate{value: amount}(deadline, inputs, outputs);

        // ETH is held in target contract
        assertEq(address(target).balance, amount);
    }

    // input ETH and ERC20
    function test_initiate_both() public {
        // add ETH input
        inputs.push(Input(address(0), amount));

        // expect Order event is initiated, ERC20 is transferred
        vm.expectEmit();
        emit Order(deadline, inputs, outputs);
        vm.expectCall(
            token, abi.encodeWithSelector(ERC20.transferFrom.selector, address(this), address(target), amount)
        );
        target.initiate{value: amount}(deadline, inputs, outputs);

        // ETH is held in target contract
        assertEq(address(target).balance, amount);
    }

    // input multiple ERC20s
    function test_initiate_multiERC20() public {
        // setup second token
        address token2 = address(new TestERC20("bye", "BYE"));
        TestERC20(token2).mint(address(this), amount * 10000);
        TestERC20(token2).approve(address(target), amount * 10000);

        // add second token input
        inputs.push(Input(token2, amount * 2));

        // expect Order event is initiated, ERC20 is transferred
        vm.expectEmit();
        emit Order(deadline, inputs, outputs);
        vm.expectCall(
            token, abi.encodeWithSelector(ERC20.transferFrom.selector, address(this), address(target), amount)
        );
        vm.expectCall(
            token2, abi.encodeWithSelector(ERC20.transferFrom.selector, address(this), address(target), amount * 2)
        );
        target.initiate(deadline, inputs, outputs);
    }

    // input multiple ETH inputs
    function test_initiate_multiETH() public {
        // change first input to ETH
        inputs[0].token = address(0);
        // add second ETH input
        inputs.push(Input(address(0), amount * 2));

        // expect Order event is initiated
        vm.expectEmit();
        emit Order(deadline, inputs, outputs);
        target.initiate{value: amount * 3}(deadline, inputs, outputs);

        // ETH is held in target contract
        assertEq(address(target).balance, amount * 3);
    }

    function test_initiate_underflowETH() public {
        // change first input to ETH
        inputs[0].token = address(0);
        // add second ETH input
        inputs.push(Input(address(0), 1));

        // total ETH inputs should be `amount` + 1; function should underflow only sending `amount`
        vm.expectRevert();
        target.initiate{value: amount}(deadline, inputs, outputs);
    }

    function test_orderExpired() public {
        vm.warp(block.timestamp + 1);

        vm.expectRevert(OrderOrigin.OrderExpired.selector);
        target.initiate(deadline, inputs, outputs);
    }

    function test_sweep_ETH() public {
        // set self as Builder
        vm.coinbase(address(this));

        // initiate an ETH order
        inputs[0].token = address(0);
        target.initiate{value: amount}(deadline, inputs, outputs);

        assertEq(address(target).balance, amount);

        // sweep ETH
        vm.expectEmit();
        emit Sweep(recipient, address(0), amount);
        target.sweep(recipient, address(0));

        assertEq(recipient.balance, amount);
    }

    function test_sweep_ERC20() public {
        // set self as Builder
        vm.coinbase(address(this));

        // send ERC20 to the contract
        TestERC20(token).transfer(address(target), amount);

        // sweep ERC20
        vm.expectEmit();
        emit Sweep(recipient, token, amount);
        vm.expectCall(token, abi.encodeWithSelector(ERC20.transfer.selector, recipient, amount));
        target.sweep(recipient, token);
    }

    function test_onlyBuilder() public {
        vm.expectRevert(OrderOrigin.OnlyBuilder.selector);
        target.sweep(recipient, token);
    }
}

contract OrdersFuzzTest is Test {
    RollupOrders public target;
    mapping(address => bool) isToken;

    uint256 deadline = block.timestamp + 100;

    event OutputFilled(uint256 indexed originChainId, address indexed recipient, address indexed token, uint256 amount);

    event Order(uint256 deadline, Input[] inputs, Output[] outputs);

    event Sweep(address indexed recipient, address indexed token, uint256 amount);

    function setUp() public {
        target = new RollupOrders();

        // deploy ERC20 tokens
        for (uint256 i; i < 15; i++) {
            address token = address(new TestERC20("hi", "HI"));
            isToken[token] = true;
        }
    }

    function testFuzz_initiate(Input[] memory fuzzInputs, Output[] memory fuzzOutputs) public {
        // can only use vm.assume 256 * 256 times, and we do 256 fuzz runs
        vm.assume(fuzzInputs.length < 256);
        // setup the fuzz test by ensuring ETH and ERC20 amounts are available
        uint256 totalETH;
        for (uint256 i; i < fuzzInputs.length; i++) {
            if (fuzzInputs[i].token == address(0)) {
                // tally up total ETH amount in the inputs
                totalETH += fuzzInputs[i].amount;
                continue;
            }

            // ERC20 inputs must be one of the tokens we've deployed
            vm.assume(isToken[fuzzInputs[i].token]);
            // mint the token amount to ensure the address has it
            TestERC20(fuzzInputs[i].token).mint(address(this), fuzzInputs[i].amount);
            // approve the target to spend the total token amount
            TestERC20(fuzzInputs[i].token).approve(address(target), type(uint256).max);
            // expect the token amount to be transferred
            vm.expectCall(
                fuzzInputs[i].token,
                abi.encodeWithSelector(
                    ERC20.transferFrom.selector, address(this), address(target), fuzzInputs[i].amount
                )
            );
        }
        // deal the total ETH amount to ensure the address has it
        vm.deal(address(this), address(this).balance + totalETH);

        vm.expectEmit();
        emit Order(deadline, fuzzInputs, fuzzOutputs);
        target.initiate{value: totalETH}(deadline, fuzzInputs, fuzzOutputs);
    }
}
