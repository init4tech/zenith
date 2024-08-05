// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.26;

// test contracts
import {Transactor} from "../src/Transact.sol";
import {Passage} from "../src/passage/Passage.sol";
// utils
import {Test, console2} from "forge-std/Test.sol";

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

    event GasConfigured(uint256 perBlock, uint256 perTransact);

    // Passage event
    event Enter(uint256 indexed rollupChainId, address indexed rollupRecipient, uint256 amount);

    function setUp() public {
        // deploy target
        passage = new Passage(block.chainid + 1, address(this), new address[](0), address(0));
        target = new Transactor(block.chainid + 1, address(this), passage, gas * 6, gas);
    }

    function test_setUp() public {
        assertEq(target.defaultRollupChainId(), block.chainid + 1);
        assertEq(target.gasAdmin(), address(this));
        assertEq(address(target.passage()), address(passage));
        assertEq(target.perBlockGasLimit(), gas * 6);
        assertEq(target.perTransactGasLimit(), gas);
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

    function test_onlyGasAdmin() public {
        vm.startPrank(address(0x01));
        vm.expectRevert(Transactor.OnlyGasAdmin.selector);
        target.configureGas(0, 0);
    }

    function test_configureGas() public {
        uint256 newPerBlock = 40_000_000;
        uint256 newPerTransact = 2_000_000;

        // configure gas
        vm.expectEmit();
        emit GasConfigured(newPerBlock, newPerTransact);
        target.configureGas(newPerBlock, newPerTransact);

        assertEq(target.perBlockGasLimit(), newPerBlock);
        assertEq(target.perTransactGasLimit(), newPerTransact);
    }
}
