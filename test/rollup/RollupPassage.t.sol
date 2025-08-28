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
