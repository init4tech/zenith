// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// test contracts
import {Passage, RollupPassage} from "../src/Passage.sol";
import {UsesPermit2} from "../src/permit2/UsesPermit2.sol";

// Permit2 deps
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {PermitHash} from "permit2/src/libraries/PermitHash.sol";

// other test utils
import {Permit2Helpers, Permit2Stub, BatchPermit2Stub, TestERC20} from "./Helpers.t.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Test, console2} from "forge-std/Test.sol";

contract SharedPermit2Test is Permit2Helpers {
    Permit2Stub permit2Contract;

    /// @notice the address signing the Permit messages and its pk
    uint256 ownerKey = 123;
    address owner = vm.addr(ownerKey);

    // permit consts
    UsesPermit2.Witness witness;
    // single permit
    UsesPermit2.Permit2 permit2;
    ISignatureTransfer.SignatureTransferDetails transferDetails;

    function _setUpPermit2(address token, uint256 amount) internal {
        vm.label(owner, "owner");

        // deploy permit2
        permit2Contract = new Permit2Stub();
        vm.label(address(permit2Contract), "permit2");

        // approve permit2
        vm.prank(owner);
        TestERC20(token).approve(address(permit2Contract), amount * 10000);

        _setupSinglePermit(token, amount);
    }

    function _setupSinglePermit(address token, uint256 amount) internal {
        // create a single permit with generic details
        permit2.permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: token, amount: amount}),
            nonce: 0,
            deadline: block.timestamp
        });
        permit2.owner = owner;
    }
}

contract PassagePermit2Test is SharedPermit2Test {
    Passage public target;

    // token consts
    address token;
    uint256 amount = 200;
    uint256 chainId = 3;
    address recipient = address(0x123);

    event EnterToken(
        uint256 indexed rollupChainId, address indexed rollupRecipient, address indexed token, uint256 amount
    );

    function setUp() public {
        // deploy token
        token = address(new TestERC20("hi", "HI"));
        TestERC20(token).mint(owner, amount * 10000);

        // configure token for passage
        address[] memory initialEnterTokens = new address[](2);
        initialEnterTokens[0] = token;

        // setup permit2 contract & permit details
        _setUpPermit2(token, amount);

        // deploy Passage
        target = new Passage(block.chainid + 1, address(this), initialEnterTokens, address(permit2Contract));
        vm.label(address(target), "passage");

        // construct Enter witness
        witness = target.enterWitness(chainId, recipient);

        // sign permit + witness
        permit2.signature = signPermit(ownerKey, address(target), permit2.permit, witness);

        // construct transfer details
        transferDetails = ISignatureTransfer.SignatureTransferDetails({to: address(target), requestedAmount: amount});
    }

    function test_enterTokenPermit2() public {
        vm.expectEmit();
        emit EnterToken(chainId, recipient, token, amount);
        vm.expectCall(
            address(permit2Contract),
            abi.encodeWithSelector(
                Permit2Stub.permitWitnessTransferFrom.selector,
                permit2.permit,
                transferDetails,
                owner,
                witness.witnessHash,
                witness.witnessTypeString,
                permit2.signature
            )
        );
        vm.expectCall(token, abi.encodeWithSelector(ERC20.transferFrom.selector, owner, address(target), amount));
        target.enterTokenPermit2(chainId, recipient, permit2);
    }

    function test_disallowedEnterPermit2() public {
        // deploy new token & approve permit2
        address newToken = address(new TestERC20("bye", "BYE"));
        TestERC20(newToken).mint(owner, amount * 10000);
        vm.prank(owner);
        TestERC20(newToken).approve(address(permit2Contract), amount * 10000);

        // edit permit token to new token
        permit2.permit.permitted.token = newToken;

        // re-sign permit + witness
        permit2.signature = signPermit(ownerKey, address(target), permit2.permit, witness);

        // expect revert DisallowedEnter
        vm.expectRevert(abi.encodeWithSelector(Passage.DisallowedEnter.selector, newToken));
        target.enterTokenPermit2(chainId, recipient, permit2);
    }
}

contract RollupPassagePermit2Test is SharedPermit2Test {
    RollupPassage public target;

    // token consts
    address token;
    uint256 amount = 200;
    uint256 chainId = 3;
    address recipient = address(0x123);

    event ExitToken(address indexed hostRecipient, address indexed token, uint256 amount);

    function setUp() public {
        // deploy token & approve permit2
        token = address(new TestERC20("hi", "HI"));
        TestERC20(token).mint(owner, amount * 10000);

        // setup permit2 contract & permit details
        _setUpPermit2(token, amount);

        // deploy Passage
        target = new RollupPassage(address(permit2Contract));
        vm.label(address(target), "passage");

        // construct Exit witness
        witness = target.exitWitness(recipient);

        // sign permit + witness
        permit2.signature = signPermit(ownerKey, address(target), permit2.permit, witness);

        // construct transfer details
        transferDetails = ISignatureTransfer.SignatureTransferDetails({to: address(target), requestedAmount: amount});
    }

    function test_exitTokenPermit2() public {
        vm.expectEmit();
        emit ExitToken(recipient, token, amount);
        vm.expectCall(
            address(permit2Contract),
            abi.encodeWithSelector(
                Permit2Stub.permitWitnessTransferFrom.selector,
                permit2.permit,
                transferDetails,
                owner,
                witness.witnessHash,
                witness.witnessTypeString,
                permit2.signature
            )
        );
        vm.expectCall(token, abi.encodeWithSelector(ERC20.transferFrom.selector, owner, address(target), amount));
        vm.expectCall(token, abi.encodeWithSelector(ERC20Burnable.burn.selector, amount));
        target.exitTokenPermit2(recipient, permit2);
    }
}
