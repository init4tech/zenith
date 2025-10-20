// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.26;

// test contracts
import {IOrders} from "../../src/orders/IOrders.sol";
import {RollupOrders} from "../../src/orders/RollupOrders.sol";
import {OrderOrigin} from "../../src/orders/OrderOrigin.sol";
// utils
import {TestERC20} from "../Helpers.t.sol";
import {SignetStdTest} from "../SignetStdTest.t.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Test, console2} from "forge-std/Test.sol";

contract OrdersFuzzTest is SignetStdTest {
    RollupOrders public target;

    event Filled(IOrders.Output[] outputs);

    event Order(uint256 deadline, IOrders.Input[] inputs, IOrders.Output[] outputs);

    event Sweep(address indexed recipient, address indexed token, uint256 amount);

    function setUp() public virtual {
        target = ROLLUP_ORDERS;
    }

    // input ERC20
    function test_initiate(uint256 deadline, IOrders.Input memory input, IOrders.Output memory output) public {
        vm.assume(deadline >= block.timestamp);

        uint256 ethAmount = 0;

        if (input.token == address(0)) {
            ethAmount += input.amount;
        } else {
            vm.mockCall(
                input.token,
                abi.encodeWithSelector(ERC20.transferFrom.selector, address(this), address(target), input.amount),
                abi.encode(true)
            );
            vm.expectCall(
                input.token,
                abi.encodeWithSelector(ERC20.transferFrom.selector, address(this), address(target), input.amount)
            );
        }

        IOrders.Input[] memory inputs = new IOrders.Input[](1);
        inputs[0] = input;
        IOrders.Output[] memory outputs = new IOrders.Output[](1);
        outputs[0] = output;

        vm.deal(address(this), ethAmount + 1 ether); // give contract some ETH

        vm.expectEmit();
        emit Order(deadline, inputs, outputs);
        target.initiate{value: ethAmount}(deadline, inputs, outputs);

        assertEq(address(target).balance, ethAmount);
    }

    function test_underflowETH(uint256 deadline, uint256 amount, IOrders.Output memory output) public {
        vm.assume(deadline >= block.timestamp);
        vm.assume(amount < type(uint256).max); // prevent overflow in vm.deal
        vm.deal(address(this), amount); // give contract some ETH

        IOrders.Input[] memory inputs = new IOrders.Input[](2);
        inputs[0] = IOrders.Input(address(0), amount);
        inputs[1] = IOrders.Input(address(0), 1);

        IOrders.Output[] memory outputs = new IOrders.Output[](1);
        outputs[0] = output;

        // total ETH inputs should be amount + 1; function should underflow only sending amount
        vm.expectRevert();
        target.initiate{value: amount}(deadline, inputs, outputs);
    }

    function test_orderExpired(uint256 deadline) public {
        vm.assume(deadline < block.timestamp);

        IOrders.Input[] memory inputs = new IOrders.Input[](0);
        IOrders.Output[] memory outputs = new IOrders.Output[](0);

        vm.expectRevert(OrderOrigin.OrderExpired.selector);
        target.initiate(deadline, inputs, outputs);
    }

    function test_sweepETH(uint256 deadline, uint256 amount, address recipient, IOrders.Output memory output) public {
        vm.assume(deadline >= block.timestamp);
        vm.assume(amount < type(uint256).max - 1000 ether); // prevent overflow in vm.deal
        vm.assume(recipient.code.length == 0 && uint160(recipient) > 0x09); // recipient is non-precompile EOA
        vm.assume(address(recipient).balance == 0); // recipient starts with zero balance
        vm.deal(address(this), amount); // give contract some ETH

        // initiate an ETH order
        IOrders.Input[] memory inputs = new IOrders.Input[](1);
        inputs[0] = IOrders.Input(address(0), amount);
        IOrders.Output[] memory outputs = new IOrders.Output[](1);
        outputs[0] = output;
        target.initiate{value: amount}(deadline, inputs, outputs);

        assertEq(address(target).balance, amount);

        // sweep ETH
        vm.expectEmit();
        emit Sweep(recipient, address(0), amount);
        target.sweep(recipient, address(0), amount);

        assertEq(address(target).balance, 0);
        assertEq(recipient.balance, amount);
    }

    function test_sweepERC20(address recipient, address token, uint256 amount) public {
        vm.assume(token != address(0));

        vm.mockCall(
            token, abi.encodeWithSelector(ERC20.transfer.selector, address(recipient), amount), abi.encode(true)
        );
        vm.expectCall(token, abi.encodeWithSelector(ERC20.transfer.selector, recipient, amount));

        // sweep ERC20
        vm.expectEmit();
        emit Sweep(recipient, token, amount);
        target.sweep(recipient, token, amount);
    }

    function test_fill(IOrders.Output memory output) public {
        vm.assume(output.amount < type(uint256).max - 1000 ether); // prevent overflow in vm.deal
        vm.assume(output.recipient.code.length == 0 && uint160(output.recipient) > 0x09); // recipient is non-precompile EOA
        vm.assume(output.token != address(vm));
        vm.deal(address(this), output.amount); // give contract some ETH

        uint256 ethAmount = 0;
        if (output.token == address(0)) {
            ethAmount += output.amount;
        } else {
            vm.mockCall(
                output.token,
                abi.encodeWithSelector(
                    ERC20.transferFrom.selector, address(this), address(output.recipient), output.amount
                ),
                abi.encode(true)
            );
            vm.expectCall(
                output.token,
                abi.encodeWithSelector(
                    ERC20.transferFrom.selector, address(this), address(output.recipient), output.amount
                )
            );
        }

        IOrders.Output[] memory outputs = new IOrders.Output[](1);
        outputs[0] = output;

        vm.expectEmit();
        emit Filled(outputs);
        target.fill{value: ethAmount}(outputs);

        // ETH is transferred to recipient
        assertEq(output.recipient.balance, ethAmount);
    }

    function test_fill_underflowETH(uint256 amount, address recipient, uint32 chainId) public {
        vm.assume(amount > 0 && amount < type(uint256).max - 1000 ether); // prevent overflow in vm.deal
        vm.assume(recipient.code.length == 0 && uint160(recipient) > 0x09); // recipient is non-precompile EOA
        vm.deal(address(this), amount); // give contract some ETH

        IOrders.Output[] memory outputs = new IOrders.Output[](2);
        outputs[0] = IOrders.Output(address(0), amount, recipient, chainId);
        outputs[1] = IOrders.Output(address(0), 1, recipient, chainId);

        // total ETH outputs should be `amount` + 1; function should underflow only sending `amount`
        vm.expectRevert();
        target.fill{value: amount}(outputs);
    }

    function test_fill_zeroETH(address recipient, uint32 chainId) public {
        vm.assume(recipient.code.length == 0 && uint160(recipient) > 0x09); // recipient is non-precompile EOA

        IOrders.Output memory output = IOrders.Output(address(0), 0, recipient, chainId);
        IOrders.Output[] memory outputs = new IOrders.Output[](1);
        outputs[0] = output;

        vm.expectEmit();
        emit Filled(outputs);
        target.fill(outputs);
    }
}
