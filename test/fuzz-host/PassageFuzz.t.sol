// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.26;

// test contracts
import {Passage} from "../../src/passage/Passage.sol";
import {RollupPassage} from "../../src/passage/RollupPassage.sol";
// utils
import {TestERC20} from "../Helpers.t.sol";
import {SignetStdTest} from "../SignetStdTest.t.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract PassageFuzzTest is SignetStdTest {
    using Address for address payable;

    Passage public target;
    address configuredToken;

    event Enter(uint256 indexed rollupChainId, address indexed rollupRecipient, uint256 amount);

    event EnterToken(
        uint256 indexed rollupChainId, address indexed rollupRecipient, address indexed token, uint256 amount
    );

    event EnterConfigured(address indexed token, bool indexed canEnter);

    event Withdrawal(address indexed token, address indexed recipient, uint256 amount);

    function setUp() public virtual {
        // deploy target
        target = HOST_PASSAGE;

        // setup token
        configuredToken = address(HOST_WETH);
        // mint WETH by sending ETH
        payable(configuredToken).sendValue(10000 ether);
        TestERC20(configuredToken).approve(address(target), 10000 ether);

        // // deploy new token that's not configured on Passage
        // newToken = address(new TestERC20("bye", "BYE", 18));
        // TestERC20(newToken).mint(address(this), amount * 10000);
        // TestERC20(newToken).approve(address(target), amount * 10000);
    }

    // only the token admin can add or remove new tokens from Passage
    function test_onlyTokenAdmin(address caller, address token, bool canEnter, address recipient, uint256 amount)
        public
    {
        vm.assume(caller != TOKEN_ADMIN);
        vm.startPrank(caller);

        vm.expectRevert(Passage.OnlyTokenAdmin.selector);
        target.configureEnter(token, canEnter);

        vm.expectRevert(Passage.OnlyTokenAdmin.selector);
        target.withdraw(token, recipient, amount);
    }

    // function test_disallowedEnter(address recipient, address newToken, uint256 amount) public {
    //     vm.assume(target.canEnter(newToken) == false);
    //     vm.expectRevert(abi.encodeWithSelector(Passage.DisallowedEnter.selector, newToken));
    //     target.enterToken(recipient, newToken, amount);
    // }

    function test_receive(uint256 amount) public {
        vm.assume(amount > 0 && amount < payable(address(this)).balance);
        vm.expectEmit();
        emit Enter(target.defaultRollupChainId(), address(this), amount);
        payable(address(target)).sendValue(amount);
    }

    function test_fallback(uint256 amount, bytes memory data) public {
        vm.assume(amount > 0 && amount < payable(address(this)).balance);
        vm.expectEmit();
        emit Enter(target.defaultRollupChainId(), address(this), amount);
        payable(address(target)).functionCallWithValue(data, amount);
    }

    function test_enter(uint256 rollupChainId, address recipient, uint256 amount) public {
        vm.assume(amount > 0 && amount < payable(address(this)).balance);
        vm.expectEmit();
        emit Enter(rollupChainId, recipient, amount);
        target.enter{value: amount}(rollupChainId, recipient);
    }

    function test_enter_defaultChain(address recipient, uint56 amount) public {
        vm.assume(amount > 0 && amount < payable(address(this)).balance);
        vm.expectEmit();
        emit Enter(target.defaultRollupChainId(), recipient, amount);
        target.enter{value: amount}(recipient);
    }

    function test_enterToken(uint256 rollupChainId, address recipient, uint256 amount) public {
        vm.assume(amount > 0 && amount < payable(address(this)).balance);
        // mint WETH of the amount
        payable(configuredToken).sendValue(amount);
        TestERC20(configuredToken).approve(address(target), amount);

        vm.expectEmit();
        emit EnterToken(rollupChainId, recipient, configuredToken, amount);
        vm.expectCall(
            configuredToken, abi.encodeWithSelector(ERC20.transferFrom.selector, address(this), address(target), amount)
        );
        target.enterToken(rollupChainId, recipient, configuredToken, amount);
    }

    function test_enterToken_defaultChain(address recipient, uint256 amount) public {
        vm.assume(amount > 0 && amount < payable(address(this)).balance);
        // mint WETH of the amount
        payable(configuredToken).sendValue(amount);
        TestERC20(configuredToken).approve(address(target), amount);

        vm.expectEmit();
        emit EnterToken(target.defaultRollupChainId(), recipient, configuredToken, amount);
        vm.expectCall(
            configuredToken, abi.encodeWithSelector(ERC20.transferFrom.selector, address(this), address(target), amount)
        );
        target.enterToken(recipient, configuredToken, amount);
    }

    function test_withdraw(address recipient, uint256 amount) public {
        vm.assume(amount > 0 && amount < payable(address(this)).balance);
        payable(configuredToken).sendValue(amount);
        IERC20(configuredToken).transfer(address(target), amount);

        vm.startPrank(TOKEN_ADMIN);
        vm.expectEmit();
        emit Withdrawal(configuredToken, recipient, amount);
        vm.expectCall(configuredToken, abi.encodeWithSelector(ERC20.transfer.selector, recipient, amount));
        target.withdraw(configuredToken, recipient, amount);
    }
}
