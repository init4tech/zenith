// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.26;

// test contracts
import {IOrders} from "../src/orders/IOrders.sol";
import {RollupOrders} from "../src/orders/Orders.sol";
import {OrderOrigin} from "../src/orders/OrderOrigin.sol";
// utils
import {TestERC20} from "./Helpers.t.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Test, console2} from "forge-std/Test.sol";

contract OrdersTest is Test {
    RollupOrders public target;
    IOrders.Input[] public inputs;
    IOrders.Output[] public outputs;

    mapping(address => bool) isToken;

    address token;
    uint32 chainId = 3;
    address recipient = address(0x123);
    uint256 amount = 200;
    uint256 deadline = block.timestamp;

    event Filled(IOrders.Output[] outputs);

    event Order(uint256 deadline, IOrders.Input[] inputs, IOrders.Output[] outputs);

    event Sweep(address indexed recipient, address indexed token, uint256 amount);

    function setUp() public {
        target = new RollupOrders(address(0));

        // setup token
        token = address(new TestERC20("hi", "HI"));
        TestERC20(token).mint(address(this), amount * 10000);
        TestERC20(token).approve(address(target), amount * 10000);
        isToken[token] = true;

        // setup Order Inputs/Outputs
        IOrders.Input memory input = IOrders.Input(token, amount);
        inputs.push(input);

        IOrders.Output memory output = IOrders.Output(token, amount, recipient, chainId);
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
        inputs.push(IOrders.Input(address(0), amount));

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
        inputs.push(IOrders.Input(token2, amount * 2));

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
        inputs.push(IOrders.Input(address(0), amount * 2));

        // expect Order event is initiated
        vm.expectEmit();
        emit Order(deadline, inputs, outputs);
        target.initiate{value: amount * 3}(deadline, inputs, outputs);

        // ETH is held in target contract
        assertEq(address(target).balance, amount * 3);
    }

    function test_underflowETH() public {
        // change first input to ETH
        inputs[0].token = address(0);
        // add second ETH input
        inputs.push(IOrders.Input(address(0), 1));

        // total ETH inputs should be amount + 1; function should underflow only sending amount
        vm.expectRevert();
        target.initiate{value: amount}(deadline, inputs, outputs);
    }

    function test_orderExpired() public {
        vm.warp(block.timestamp + 1);

        vm.expectRevert(OrderOrigin.OrderExpired.selector);
        target.initiate(deadline, inputs, outputs);
    }

    function test_sweepETH() public {
        // set self as Builder
        vm.coinbase(address(this));

        // initiate an ETH order
        inputs[0].token = address(0);
        target.initiate{value: amount}(deadline, inputs, outputs);

        assertEq(address(target).balance, amount);

        // sweep ETH
        vm.expectEmit();
        emit Sweep(recipient, address(0), amount);
        target.sweep(recipient, address(0), amount);

        assertEq(recipient.balance, amount);
    }

    function test_sweepERC20() public {
        // set self as Builder
        vm.coinbase(address(this));

        // send ERC20 to the contract
        TestERC20(token).transfer(address(target), amount);

        // sweep ERC20
        vm.expectEmit();
        emit Sweep(recipient, token, amount);
        vm.expectCall(token, abi.encodeWithSelector(ERC20.transfer.selector, recipient, amount));
        target.sweep(recipient, token, amount);
    }

    function test_fill_ETH() public {
        outputs[0].token = address(0);

        vm.expectEmit();
        emit Filled(outputs);
        target.fill{value: amount}(outputs);

        // ETH is transferred to recipient
        assertEq(recipient.balance, amount);
    }

    function test_fill_ERC20() public {
        vm.expectEmit();
        emit Filled(outputs);
        vm.expectCall(token, abi.encodeWithSelector(ERC20.transferFrom.selector, address(this), recipient, amount));
        target.fill(outputs);
    }

    function test_fill_both() public {
        // add ETH output
        outputs.push(IOrders.Output(address(0), amount * 2, recipient, chainId));

        // expect Outputs are filled, ERC20 is transferred
        vm.expectEmit();
        emit Filled(outputs);
        vm.expectCall(token, abi.encodeWithSelector(ERC20.transferFrom.selector, address(this), recipient, amount));
        target.fill{value: amount * 2}(outputs);

        // ETH is transferred to recipient
        assertEq(recipient.balance, amount * 2);
    }

    // fill multiple ETH outputs
    function test_fill_multiETH() public {
        // change first output to ETH
        outputs[0].token = address(0);
        // add second ETH oputput
        outputs.push(IOrders.Output(address(0), amount * 2, recipient, chainId));

        // expect Order event is initiated
        vm.expectEmit();
        emit Filled(outputs);
        target.fill{value: amount * 3}(outputs);

        // ETH is transferred to recipient
        assertEq(recipient.balance, amount * 3);
    }

    function test_fill_underflowETH() public {
        // change first output to ETH
        outputs[0].token = address(0);
        // add second ETH output
        outputs.push(IOrders.Output(address(0), 1, recipient, chainId));

        // total ETH outputs should be `amount` + 1; function should underflow only sending `amount`
        vm.expectRevert();
        target.fill{value: amount}(outputs);
    }
}
