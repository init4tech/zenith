// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

// test contracts
import {Passage, RollupPassage} from "../src/Passage.sol";
import {PassagePermit2, UsesPermit2} from "../src/permit2/UsesPermit2.sol";
import {RollupOrders} from "../src/Orders.sol";
import {IOrders} from "../src/interfaces/IOrders.sol";

// Permit2 deps
// import {Permit2} from "permit2/src/Permit2.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {PermitHash} from "permit2/src/libraries/PermitHash.sol";

// other test utils
import {Permit2Helpers, Permit2Stub, BatchPermit2Stub, TestERC20} from "./Helpers.t.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Test, console2} from "forge-std/Test.sol";

// TODO: test that witness encoding is valid
// TODO: fix gas metering in the tests

contract SharedPermit2Test is Permit2Helpers {
    Permit2Stub permit2Contract;
    BatchPermit2Stub permit2BatchContract;

    /// @notice the address signing the Permit messages and its pk
    uint256 ownerKey = 123;
    address owner = vm.addr(ownerKey);

    // permit consts
    UsesPermit2.Witness witness;
    // single permit
    UsesPermit2.Permit2 permit2;
    ISignatureTransfer.SignatureTransferDetails transferDetails;
    // batch permit
    UsesPermit2.Permit2Batch permit2Batch;
    ISignatureTransfer.SignatureTransferDetails[] transferDetailsBatch;

    function _setUpPermit2(address token, uint256 amount) internal {
        vm.label(owner, "owner");

        // deploy permit2
        permit2Contract = new Permit2Stub();
        vm.label(address(permit2Contract), "permit2");

        // deploy batch permit2
        permit2BatchContract = new BatchPermit2Stub();
        vm.label(address(permit2BatchContract), "permit2Batch");

        // approve permit2 & batch permit2
        vm.prank(owner);
        TestERC20(token).approve(address(permit2Contract), amount * 10000);
        vm.prank(owner);
        TestERC20(token).approve(address(permit2BatchContract), amount * 10000);

        // create a single permit with generic details
        permit2.permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: token, amount: amount}),
            nonce: 0,
            deadline: block.timestamp
        });
        permit2.owner = owner;

        // create a batch permit with generic details
        permit2Batch.permit.permitted.push(ISignatureTransfer.TokenPermissions({token: token, amount: amount}));
        permit2Batch.permit.nonce = 0;
        permit2Batch.permit.deadline = block.timestamp;
        permit2Batch.owner = owner;
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

contract OrderOriginPermit2Test is SharedPermit2Test {
    RollupOrders public target;

    IOrders.Input[] public inputs;
    IOrders.Output[] public outputs;

    mapping(address => bool) isToken;

    address token;
    uint32 chainId = 3;
    address recipient = address(0x123);
    uint256 amount = 200;
    uint256 deadline = block.timestamp;

    address tokenRecipient = address(0xdeadbeef);

    event Order(uint256 deadline, IOrders.Input[] inputs, IOrders.Output[] outputs);

    event Filled(IOrders.Output[] outputs);

    function setUp() public {
        // deploy token
        token = address(new TestERC20("hi", "HI"));
        TestERC20(token).mint(owner, amount * 10000);
        isToken[token] = true;

        // setup permit2 contract & permit details
        _setUpPermit2(token, amount);

        // deploy Orders contract
        target = new RollupOrders(address(permit2BatchContract));
        vm.label(address(target), "orders");

        // setup Order Inputs/Outputs
        IOrders.Input memory input = IOrders.Input(token, amount);
        inputs.push(input);

        IOrders.Output memory output = IOrders.Output(token, amount, recipient, chainId);
        outputs.push(output);

        // construct Orders witness
        witness = target.outputWitness(outputs);

        // sign permit + witness
        permit2.signature = signPermit(ownerKey, address(target), permit2Batch.permit, witness);

        // construct transfer details
        transferDetailsBatch.push(
            ISignatureTransfer.SignatureTransferDetails({to: tokenRecipient, requestedAmount: amount})
        );
    }

    function test_initiatePermit2() public {
        // expect Order event is initiated, ERC20 is transferred
        vm.expectEmit();
        emit Order(deadline, inputs, outputs);
        vm.expectCall(
            address(permit2BatchContract),
            abi.encodeWithSelector(
                BatchPermit2Stub.permitWitnessTransferFrom.selector,
                permit2Batch.permit,
                transferDetailsBatch,
                owner,
                witness.witnessHash,
                witness.witnessTypeString,
                permit2Batch.signature
            )
        );
        vm.expectCall(token, abi.encodeWithSelector(ERC20.transferFrom.selector, owner, tokenRecipient, amount));
        target.initiatePermit2(tokenRecipient, outputs, permit2Batch);
    }

    // input multiple ERC20s
    function test_initiatePermit2_multi() public {
        // setup second token
        address token2 = address(new TestERC20("bye", "BYE"));
        TestERC20(token2).mint(owner, amount * 10000);
        vm.prank(owner);
        TestERC20(token2).approve(address(permit2BatchContract), amount * 10000);

        // add second token input
        inputs.push(IOrders.Input(token2, amount * 2));

        // add TokenPermissions
        permit2Batch.permit.permitted.push(ISignatureTransfer.TokenPermissions({token: token2, amount: amount * 2}));

        // add TransferDetails
        transferDetailsBatch.push(
            ISignatureTransfer.SignatureTransferDetails({to: tokenRecipient, requestedAmount: amount * 2})
        );

        // re-sign new permit
        permit2.signature = signPermit(ownerKey, address(target), permit2Batch.permit, witness);

        // expect Order event is emitted, ERC20 is transferred
        vm.expectEmit();
        emit Order(deadline, inputs, outputs);
        vm.expectCall(token, abi.encodeWithSelector(ERC20.transferFrom.selector, owner, tokenRecipient, amount));
        vm.expectCall(token2, abi.encodeWithSelector(ERC20.transferFrom.selector, owner, tokenRecipient, amount * 2));
        target.initiatePermit2(tokenRecipient, outputs, permit2Batch);
    }

    function test_fillPermit2() public {
        vm.expectEmit();
        emit Filled(outputs);
        vm.expectCall(token, abi.encodeWithSelector(ERC20.transferFrom.selector, owner, recipient, amount));
        target.fillPermit2(outputs, permit2Batch);
    }

    function test_fillPermit2_multi() public {
        // setup second token
        address token2 = address(new TestERC20("bye", "BYE"));
        TestERC20(token2).mint(owner, amount * 10000);
        vm.prank(owner);
        TestERC20(token2).approve(address(permit2BatchContract), amount * 10000);

        // add second token output
        outputs.push(IOrders.Output(token2, amount * 2, recipient, chainId));

        // add TokenPermissions
        permit2Batch.permit.permitted.push(ISignatureTransfer.TokenPermissions({token: token2, amount: amount * 2}));

        // add TransferDetails
        transferDetailsBatch.push(
            ISignatureTransfer.SignatureTransferDetails({to: recipient, requestedAmount: amount * 2})
        );

        // re-sign new permit
        permit2.signature = signPermit(ownerKey, address(target), permit2Batch.permit, witness);

        // expect Filled event is emitted, ERC20 is transferred
        vm.expectEmit();
        emit Filled(outputs);
        vm.expectCall(token, abi.encodeWithSelector(ERC20.transferFrom.selector, owner, recipient, amount));
        vm.expectCall(token2, abi.encodeWithSelector(ERC20.transferFrom.selector, owner, recipient, amount * 2));
        target.fillPermit2(outputs, permit2Batch);
    }
}
