// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// test contracts
import {Passage} from "../src/passage/Passage.sol";
import {RollupPassage} from "../src/passage/RollupPassage.sol";
// utils
import {TestERC20} from "./Helpers.t.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Test, console2} from "forge-std/Test.sol";

contract PassageTest is Test {
    Passage public target;
    address token;
    address newToken;
    uint64 chainId = 3;
    address recipient = address(0x123);
    uint256 amount = 200;

    address to = address(0x01);
    bytes data = abi.encodeWithSelector(ERC20.transfer.selector, recipient, amount);
    uint256 value = 100;
    uint256 gas = 10_000_000;
    uint256 maxFeePerGas = 50;

    event Enter(uint64 indexed rollupChainId, address indexed rollupRecipient, uint256 amount);

    event EnterToken(
        uint64 indexed rollupChainId, address indexed rollupRecipient, address indexed token, uint256 amount
    );

    event Transact(
        uint64 indexed rollupChainId,
        address indexed sender,
        address indexed to,
        bytes data,
        uint256 value,
        uint256 gas,
        uint256 maxFeePerGas
    );

    event Withdrawal(address indexed token, address indexed recipient, uint256 amount);

    event EnterConfigured(address indexed token, bool indexed canEnter);

    function setUp() public {
        // deploy token one, configured at deploy time
        token = address(new TestERC20("hi", "HI"));
        TestERC20(token).mint(address(this), amount * 10000);

        // deploy target
        address[] memory initialEnterTokens = new address[](1);
        initialEnterTokens[0] = token;
        target = new Passage(uint64(uint64(block.chainid + 1)), address(this), initialEnterTokens, address(0));
        TestERC20(token).approve(address(target), amount * 10000);

        // deploy token two, don't configure
        newToken = address(new TestERC20("bye", "BYE"));
        TestERC20(newToken).mint(address(this), amount * 10000);
        TestERC20(newToken).approve(address(target), amount * 10000);
    }

    function test_setUp() public {
        assertEq(target.defaultRollupChainId(), uint64(block.chainid + 1));
        assertEq(target.tokenAdmin(), address(this));
        assertTrue(target.canEnter(token));
        assertFalse(target.canEnter(newToken));
    }

    function test_onlyTokenAdmin() public {
        vm.startPrank(address(0x01));
        vm.expectRevert(Passage.OnlyTokenAdmin.selector);
        target.withdraw(token, recipient, amount);

        vm.expectRevert(Passage.OnlyTokenAdmin.selector);
        target.configureEnter(token, true);
    }

    function test_disallowedEnter() public {
        vm.expectRevert(abi.encodeWithSelector(Passage.DisallowedEnter.selector, newToken));
        target.enterToken(recipient, newToken, amount);
    }

    function test_configureEnter() public {
        // enter not allowed by default
        assertFalse(target.canEnter(newToken));
        vm.expectRevert(abi.encodeWithSelector(Passage.DisallowedEnter.selector, newToken));
        target.enterToken(chainId, recipient, newToken, amount);

        // allow enter
        vm.expectEmit();
        emit EnterConfigured(newToken, true);
        target.configureEnter(newToken, true);

        // enter is allowed
        assertTrue(target.canEnter(newToken));
        vm.expectEmit();
        emit EnterToken(chainId, recipient, newToken, amount);
        target.enterToken(chainId, recipient, newToken, amount);

        // disallow enter
        vm.expectEmit();
        emit EnterConfigured(newToken, false);
        target.configureEnter(newToken, false);

        // enter not allowed again
        assertFalse(target.canEnter(newToken));
        vm.expectRevert(abi.encodeWithSelector(Passage.DisallowedEnter.selector, newToken));
        target.enterToken(chainId, recipient, newToken, amount);
    }

    function test_receive() public {
        vm.expectEmit();
        emit Enter(target.defaultRollupChainId(), address(this), amount);
        address(target).call{value: amount}("");
    }

    function test_fallback() public {
        vm.expectEmit();
        emit Enter(target.defaultRollupChainId(), address(this), amount);
        address(target).call{value: amount}("0xabcd");
    }

    function test_enter() public {
        vm.expectEmit();
        emit Enter(chainId, recipient, amount);
        target.enter{value: amount}(chainId, recipient);
    }

    function test_enter_defaultChain() public {
        vm.expectEmit();
        emit Enter(target.defaultRollupChainId(), recipient, amount);
        target.enter{value: amount}(recipient);
    }

    function test_enterToken() public {
        vm.expectEmit();
        emit EnterToken(chainId, recipient, token, amount);
        vm.expectCall(
            token, abi.encodeWithSelector(ERC20.transferFrom.selector, address(this), address(target), amount)
        );
        target.enterToken(chainId, recipient, token, amount);
    }

    function test_enterToken_defaultChain() public {
        vm.expectEmit();
        emit EnterToken(target.defaultRollupChainId(), recipient, token, amount);
        vm.expectCall(
            token, abi.encodeWithSelector(ERC20.transferFrom.selector, address(this), address(target), amount)
        );
        target.enterToken(recipient, token, amount);
    }

    function test_withdraw() public {
        TestERC20(token).mint(address(target), amount);

        vm.expectEmit();
        emit Withdrawal(token, recipient, amount);
        vm.expectCall(token, abi.encodeWithSelector(ERC20.transfer.selector, recipient, amount));
        target.withdraw(token, recipient, amount);
    }
}

contract RollupPassageTest is Test {
    RollupPassage public target;
    address token;
    address recipient = address(0x123);
    uint256 amount = 200;

    event Exit(address indexed hostRecipient, uint256 amount);

    event ExitToken(address indexed hostRecipient, address indexed token, uint256 amount);

    function setUp() public {
        // deploy target
        target = new RollupPassage(address(0));

        // deploy token
        token = address(new TestERC20("hi", "HI"));
        TestERC20(token).mint(address(this), amount * 10000);
        TestERC20(token).approve(address(target), amount * 10000);
    }

    function test_receive() public {
        vm.expectEmit();
        emit Exit(address(this), amount);
        address(target).call{value: amount}("");
    }

    function test_fallback() public {
        vm.expectEmit();
        emit Exit(address(this), amount);
        address(target).call{value: amount}("0xabcd");
    }

    function test_exit() public {
        vm.expectEmit();
        emit Exit(recipient, amount);
        target.exit{value: amount}(recipient);
    }

    function test_exitToken() public {
        vm.expectEmit();
        emit ExitToken(recipient, token, amount);
        vm.expectCall(
            token, abi.encodeWithSelector(ERC20.transferFrom.selector, address(this), address(target), amount)
        );
        vm.expectCall(token, abi.encodeWithSelector(ERC20Burnable.burn.selector, amount));
        target.exitToken(recipient, token, amount);
    }
}
