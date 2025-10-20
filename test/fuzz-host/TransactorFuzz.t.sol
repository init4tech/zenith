// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.26;

// test contracts
import {Transactor} from "../../src/Transactor.sol";
import {Passage} from "../../src/passage/Passage.sol";
// utils
import {SignetStdTest} from "../SignetStdTest.t.sol";
import {Test, console2} from "forge-std/Test.sol";

contract TransactFuzzTest is SignetStdTest {
    Transactor public target;

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

    function setUp() public virtual {
        // deploy target
        target = HOST_TRANSACTOR;
    }

    function test_transact(
        uint256 rollupChainId,
        address sender,
        address to,
        bytes memory data,
        uint256 value,
        uint256 gas,
        uint256 maxFeePerGas
    ) public {
        vm.assume(gas <= target.perTransactGasLimit() && gas <= target.perBlockGasLimit());

        vm.startPrank(sender);
        vm.expectEmit(address(target));
        emit Transact(rollupChainId, sender, to, data, value, gas, maxFeePerGas);
        target.transact(rollupChainId, to, data, value, gas, maxFeePerGas);
    }

    function test_enterTransact_emitsEnter(
        uint256 rollupChainId,
        address to,
        bytes memory data,
        uint256 value,
        uint256 gas,
        uint256 maxFeePerGas,
        uint256 amount
    ) public {
        vm.assume(gas <= target.perTransactGasLimit() && gas <= target.perBlockGasLimit());
        vm.assume(amount > 0 && amount < payable(address(this)).balance);

        vm.expectEmit(address(HOST_PASSAGE));
        emit Enter(rollupChainId, address(this), amount);
        target.transact{value: amount}(rollupChainId, to, data, value, gas, maxFeePerGas);
    }

    function test_enterTransact_emitsTransact(
        uint256 rollupChainId,
        address to,
        bytes memory data,
        uint256 value,
        uint256 gas,
        uint256 maxFeePerGas,
        uint256 amount
    ) public {
        vm.assume(gas <= target.perTransactGasLimit() && gas <= target.perBlockGasLimit());
        vm.assume(amount > 0 && amount < payable(address(this)).balance);

        vm.expectEmit(address(target));
        emit Transact(rollupChainId, address(this), to, data, value, gas, maxFeePerGas);
        target.transact{value: amount}(rollupChainId, to, data, value, gas, maxFeePerGas);
    }

    function test_transact_defaultChain(
        address sender,
        address to,
        bytes memory data,
        uint256 value,
        uint256 gas,
        uint256 maxFeePerGas
    ) public {
        vm.assume(gas <= target.perTransactGasLimit() && gas <= target.perBlockGasLimit());

        vm.startPrank(sender);
        vm.expectEmit(address(target));
        emit Transact(ROLLUP_CHAIN_ID, sender, to, data, value, gas, maxFeePerGas);
        target.transact(to, data, value, gas, maxFeePerGas);
    }

    function test_transactWithValue_defaultChain_emitsEnter(
        address to,
        bytes memory data,
        uint256 value,
        uint256 gas,
        uint256 maxFeePerGas,
        uint256 amount
    ) public {
        vm.assume(gas <= target.perTransactGasLimit() && gas <= target.perBlockGasLimit());
        vm.assume(amount > 0 && amount < payable(address(this)).balance);

        vm.expectEmit(address(HOST_PASSAGE));
        emit Enter(ROLLUP_CHAIN_ID, address(this), amount);
        target.transact{value: amount}(to, data, value, gas, maxFeePerGas);
    }

    function test_transactWithValue_defaultChain_emitsTransact(
        address to,
        bytes memory data,
        uint256 value,
        uint256 gas,
        uint256 maxFeePerGas,
        uint256 amount
    ) public {
        vm.assume(gas <= target.perTransactGasLimit() && gas <= target.perBlockGasLimit());
        vm.assume(amount > 0 && amount < payable(address(this)).balance);

        vm.expectEmit(address(target));
        emit Transact(ROLLUP_CHAIN_ID, address(this), to, data, value, gas, maxFeePerGas);
        target.transact{value: amount}(to, data, value, gas, maxFeePerGas);
    }

    function test_enterTransact_defaultChain_emitsEnter(
        uint256 rollupChainId,
        address recipient,
        address to,
        bytes memory data,
        uint256 value,
        uint256 gas,
        uint256 maxFeePerGas,
        uint256 amount
    ) public {
        vm.assume(gas <= target.perTransactGasLimit() && gas <= target.perBlockGasLimit());
        vm.assume(amount > 0 && amount < payable(address(this)).balance);

        vm.expectEmit(address(HOST_PASSAGE));
        emit Enter(rollupChainId, recipient, amount);
        target.enterTransact{value: amount}(rollupChainId, recipient, to, data, value, gas, maxFeePerGas);
    }

    function test_transactWithValue_defaultChain_emitsTransact(
        uint256 rollupChainId,
        address recipient,
        address to,
        bytes memory data,
        uint256 value,
        uint256 gas,
        uint256 maxFeePerGas,
        uint256 amount
    ) public {
        vm.assume(gas <= target.perTransactGasLimit() && gas <= target.perBlockGasLimit());
        vm.assume(amount > 0 && amount < payable(address(this)).balance);

        vm.expectEmit(address(target));
        emit Transact(rollupChainId, address(this), to, data, value, gas, maxFeePerGas);
        target.enterTransact{value: amount}(rollupChainId, recipient, to, data, value, gas, maxFeePerGas);
    }

    function test_transact_perTransactGasLimit(
        uint256 rollupChainId,
        address to,
        bytes memory data,
        uint256 value,
        uint256 gas,
        uint256 maxFeePerGas
    ) public {
        vm.assume(gas > target.perTransactGasLimit());
        vm.expectRevert(Transactor.PerTransactGasLimit.selector);
        target.transact(rollupChainId, to, data, value, gas, maxFeePerGas);
    }

    function test_onlyGasAdmin(address caller, uint256 perBlockGas, uint256 perTransactGas) public {
        vm.assume(caller != GAS_ADMIN);
        vm.startPrank(caller);

        vm.expectRevert(Transactor.OnlyGasAdmin.selector);
        target.configureGas(perBlockGas, perTransactGas);
    }

    function test_configureGas(uint256 newPerBlock, uint256 newPerTransact) public {
        // configure gas
        vm.startPrank(GAS_ADMIN);
        vm.expectEmit();
        emit GasConfigured(newPerBlock, newPerTransact);
        target.configureGas(newPerBlock, newPerTransact);
        vm.stopPrank();

        assertEq(target.perBlockGasLimit(), newPerBlock);
        assertEq(target.perTransactGasLimit(), newPerTransact);
    }
}
