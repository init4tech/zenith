// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.26;

// test contracts
import {Passage} from "../src/passage/Passage.sol";
import {RollupPassage} from "../src/passage/RollupPassage.sol";
// utils
import {TestERC20} from "./Helpers.t.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {Test, console2} from "forge-std/Test.sol";
import {SignetStdTest} from "./SignetStdTest.t.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract PassageTest is SignetStdTest {
    using Address for address payable;

    Passage public target;
    address token;
    address newToken;
    address recipient = address(0x123);
    uint256 amount = 200;

    event Enter(uint256 indexed rollupChainId, address indexed rollupRecipient, uint256 amount);

    event EnterToken(
        uint256 indexed rollupChainId, address indexed rollupRecipient, address indexed token, uint256 amount
    );

    event EnterConfigured(address indexed token, bool indexed canEnter);

    event Withdrawal(address indexed token, address indexed recipient, uint256 amount);

    function setUp() public {
        // deploy target
        target = HOST_PASSAGE;

        // setup token
        token = address(HOST_WETH);
        // mint WETH by sending ETH
        // TODO - this will fail until real WETH is deployed for the test SignetStd
        payable(token).sendValue(amount * 10000);
        TestERC20(token).approve(address(target), amount * 10000);

        // deploy new token that's not configured on Passage
        newToken = address(new TestERC20("bye", "BYE", 18));
        TestERC20(newToken).mint(address(this), amount * 10000);
        TestERC20(newToken).approve(address(target), amount * 10000);
    }

    function test_setUp() public {
        assertEq(target.defaultRollupChainId(), ROLLUP_CHAIN_ID);
        assertEq(target.tokenAdmin(), TOKEN_ADMIN);
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
        target.enterToken(ROLLUP_CHAIN_ID, recipient, newToken, amount);

        // allow enter
        vm.startPrank(TOKEN_ADMIN);
        vm.expectEmit();
        emit EnterConfigured(newToken, true);
        target.configureEnter(newToken, true);
        vm.stopPrank();

        // enter is allowed
        assertTrue(target.canEnter(newToken));
        vm.expectEmit();
        emit EnterToken(ROLLUP_CHAIN_ID, recipient, newToken, amount);
        target.enterToken(ROLLUP_CHAIN_ID, recipient, newToken, amount);

        // disallow enter
        vm.startPrank(TOKEN_ADMIN);
        vm.expectEmit();
        emit EnterConfigured(newToken, false);
        target.configureEnter(newToken, false);
        vm.stopPrank();

        // enter not allowed again
        assertFalse(target.canEnter(newToken));
        vm.expectRevert(abi.encodeWithSelector(Passage.DisallowedEnter.selector, newToken));
        target.enterToken(ROLLUP_CHAIN_ID, recipient, newToken, amount);
    }

    function test_receive() public {
        vm.expectEmit();
        emit Enter(target.defaultRollupChainId(), address(this), amount);
        payable(address(target)).sendValue(amount);
    }

    function test_fallback() public {
        vm.expectEmit();
        emit Enter(target.defaultRollupChainId(), address(this), amount);
        payable(address(target)).functionCallWithValue("0xabcd", amount);
    }

    function test_enter() public {
        vm.expectEmit();
        emit Enter(ROLLUP_CHAIN_ID, recipient, amount);
        target.enter{value: amount}(ROLLUP_CHAIN_ID, recipient);
    }

    function test_enter_defaultChain() public {
        vm.expectEmit();
        emit Enter(target.defaultRollupChainId(), recipient, amount);
        target.enter{value: amount}(recipient);
    }

    function test_enterToken() public {
        vm.expectEmit();
        emit EnterToken(ROLLUP_CHAIN_ID, recipient, token, amount);
        vm.expectCall(
            token, abi.encodeWithSelector(ERC20.transferFrom.selector, address(this), address(target), amount)
        );
        target.enterToken(ROLLUP_CHAIN_ID, recipient, token, amount);
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
        IERC20(token).transfer(address(target), amount);

        vm.startPrank(TOKEN_ADMIN);
        vm.expectEmit();
        emit Withdrawal(token, recipient, amount);
        vm.expectCall(token, abi.encodeWithSelector(ERC20.transfer.selector, recipient, amount));
        target.withdraw(token, recipient, amount);
    }
}

contract RollupPassageTest is SignetStdTest {
    using Address for address payable;

    RollupPassage public target;
    address token;
    address recipient = address(0x123);
    uint256 amount = 200;

    event Exit(address indexed hostRecipient, uint256 amount);

    event ExitToken(address indexed hostRecipient, address indexed token, uint256 amount);

    function setUp() public virtual {
        // setup target
        target = ROLLUP_PASSAGE;

        // setup token
        token = address(ROLLUP_WETH);
        vm.prank(ROLLUP_MINTER);
        TestERC20(token).mint(address(this), amount * 10000);
        TestERC20(token).approve(address(target), amount * 10000);
    }

    function test_receive() public {
        vm.expectEmit();
        emit Exit(address(this), amount);
        payable(address(target)).sendValue(amount);
    }

    function test_fallback() public {
        vm.expectEmit();
        emit Exit(address(this), amount);
        payable(address(target)).functionCallWithValue("0xabcd", amount);
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
