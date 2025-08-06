// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.26;

// test contracts
import {Passage} from "../src/passage/Passage.sol";
import {RollupPassage} from "../src/passage/RollupPassage.sol";
import {UsesPermit2} from "../src/UsesPermit2.sol";
// utils
import {Permit2Helpers, ISinglePermit, TestERC20} from "./Helpers.t.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Test, console2} from "forge-std/Test.sol";
import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";

contract PassagePermit2Test is Permit2Helpers {
    using Address for address payable;

    Passage public target;

    // token consts
    address token;
    uint256 amount = 200;
    address recipient = address(0x123);

    event EnterToken(
        uint256 indexed rollupChainId, address indexed rollupRecipient, address indexed token, uint256 amount
    );

    function setUp() public virtual {
        vm.createSelectFork("https://ethereum-rpc.publicnode.com");
        // re-setup Std after forking -- TODO -- change this so that setupStd() does the forking itself? idk?
        setupStd();

        // setup Passage
        target = HOST_PASSAGE;
        vm.label(address(target), "passage");
        vm.label(address(PERMIT2), "permit2");
        vm.label(owner, "owner");

        // setup token
        token = address(HOST_WETH);
        // mint WETH by sending ETH
        payable(token).sendValue(amount * 10000);
        // send WETH to Permit2 signer
        TestERC20(token).transfer(owner, amount * 10000);
        // approve permit2 from owner
        vm.prank(owner);
        TestERC20(token).approve(address(PERMIT2), amount * 10000);

        // set basic permit details
        singlePermit.permit.nonce = 0;
        singlePermit.permit.deadline = block.timestamp;
        singlePermit.owner = owner;
        singlePermit.permit.permitted = ISignatureTransfer.TokenPermissions({token: token, amount: amount});
        singleTransferDetails =
            ISignatureTransfer.SignatureTransferDetails({to: address(target), requestedAmount: amount});

        // construct Enter witness
        witness = target.enterWitness(ROLLUP_CHAIN_ID, recipient);

        // sign permit + witness
        singlePermit.signature = signPermit(ownerKey, address(target), singlePermit.permit, witness);
    }

    function test_enterTokenPermit2() public {
        vm.expectEmit();
        emit EnterToken(ROLLUP_CHAIN_ID, recipient, token, amount);
        vm.expectCall(
            address(PERMIT2),
            abi.encodeWithSelector(
                ISinglePermit.permitWitnessTransferFrom.selector,
                singlePermit.permit,
                singleTransferDetails,
                owner,
                witness.witnessHash,
                witness.witnessTypeString,
                singlePermit.signature
            )
        );
        vm.expectCall(token, abi.encodeWithSelector(ERC20.transferFrom.selector, owner, address(target), amount));
        target.enterTokenPermit2(ROLLUP_CHAIN_ID, recipient, singlePermit);
    }

    function test_disallowedEnterPermit2() public {
        // deploy new token & approve permit2
        address newToken = address(new TestERC20("bye", "BYE", 18));
        // mint tokens to owner
        TestERC20(newToken).mint(owner, amount * 10000);
        // approve permit2 from owner
        vm.prank(owner);
        TestERC20(newToken).approve(address(PERMIT2), amount * 10000);

        // modify permit details
        singlePermit.permit.permitted = ISignatureTransfer.TokenPermissions({token: newToken, amount: amount});

        // re-sign permit + same recipient witness
        singlePermit.signature = signPermit(ownerKey, address(target), singlePermit.permit, witness);

        // expect revert DisallowedEnter
        vm.expectRevert(abi.encodeWithSelector(Passage.DisallowedEnter.selector, newToken));
        target.enterTokenPermit2(ROLLUP_CHAIN_ID, recipient, singlePermit);
    }
}

contract RollupPassagePermit2Test is Permit2Helpers {
    RollupPassage public target;

    // token consts
    address token;
    uint256 amount = 200;
    address recipient = address(0x123);

    event ExitToken(address indexed hostRecipient, address indexed token, uint256 amount);

    function setUp() public virtual {
        vm.createSelectFork("https://ethereum-rpc.publicnode.com");
        setupStd();

        // setup RollupPassage
        target = ROLLUP_PASSAGE;
        vm.label(address(target), "rollup_passage");
        vm.label(address(PERMIT2), "permit2");
        vm.label(owner, "owner");

        // setup token
        token = address(ROLLUP_WBTC);
        // mint tokens to owner
        vm.prank(ROLLUP_MINTER);
        TestERC20(token).mint(owner, amount * 10000);
        // approve permit2 from owner
        vm.prank(owner);
        TestERC20(token).approve(address(PERMIT2), amount * 10000);

        // set basic permit details
        singlePermit.permit.nonce = 0;
        singlePermit.permit.deadline = block.timestamp;
        singlePermit.owner = owner;
        singlePermit.permit.permitted = ISignatureTransfer.TokenPermissions({token: token, amount: amount});
        singleTransferDetails =
            ISignatureTransfer.SignatureTransferDetails({to: address(target), requestedAmount: amount});

        // construct Exit witness
        witness = target.exitWitness(recipient);

        // sign permit + witness
        singlePermit.signature = signPermit(ownerKey, address(target), singlePermit.permit, witness);
    }

    function test_exitTokenPermit2() public {
        vm.expectEmit();
        emit ExitToken(recipient, token, amount);
        vm.expectCall(
            address(PERMIT2),
            abi.encodeWithSelector(
                ISinglePermit.permitWitnessTransferFrom.selector,
                singlePermit.permit,
                singleTransferDetails,
                owner,
                witness.witnessHash,
                witness.witnessTypeString,
                singlePermit.signature
            )
        );
        vm.expectCall(token, abi.encodeWithSelector(ERC20.transferFrom.selector, owner, address(target), amount));
        vm.expectCall(token, abi.encodeWithSelector(ERC20Burnable.burn.selector, amount));
        target.exitTokenPermit2(recipient, singlePermit);
    }
}
