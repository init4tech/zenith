// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.26;

// test contracts
import {RollupOrders} from "../src/orders/RollupOrders.sol";
import {IOrders} from "../src/orders/IOrders.sol";
import {UsesPermit2} from "../src/UsesPermit2.sol";
// utils
import {Permit2Helpers, IBatchPermit, TestERC20} from "./Helpers.t.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {Test, console2} from "forge-std/Test.sol";

contract Permit2BatchTest is Permit2Helpers {
    // batch permit
    UsesPermit2.Permit2Batch permit2;
    ISignatureTransfer.SignatureTransferDetails[] transferDetails;

    function _setupBatchPermit(address token, uint256 amount) internal {
        // create a batch permit with generic details
        permit2.permit.permitted.push(ISignatureTransfer.TokenPermissions({token: token, amount: amount}));
        permit2.permit.nonce = 0;
        permit2.permit.deadline = block.timestamp;
        permit2.owner = owner;
    }
}

contract OrderOriginPermit2Test is Permit2BatchTest {
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
        vm.createSelectFork("https://ethereum-rpc.publicnode.com");
        // deploy token
        token = address(new TestERC20("hi", "HI"));
        TestERC20(token).mint(owner, amount * 10000);
        isToken[token] = true;

        // setup permit2 contract & permit details
        _setUpPermit2(token, amount);
        _setupBatchPermit(token, amount);

        // deploy Orders contract
        target = new RollupOrders(address(permit2Contract));
        vm.label(address(target), "orders");

        // setup Order Inputs/Outputs
        IOrders.Input memory input = IOrders.Input(token, amount);
        inputs.push(input);

        IOrders.Output memory output = IOrders.Output(token, amount, recipient, chainId);
        outputs.push(output);

        // construct Orders witness
        witness = target.outputWitness(outputs);

        // sign permit + witness
        permit2.signature = signPermit(ownerKey, address(target), permit2.permit, witness);
    }

    function test_initiatePermit2() public {
        // construct transfer details
        transferDetails.push(ISignatureTransfer.SignatureTransferDetails({to: tokenRecipient, requestedAmount: amount}));

        // expect Order event is initiated, ERC20 is transferred
        vm.expectEmit();
        emit Order(permit2.permit.deadline, inputs, outputs);
        vm.expectCall(
            address(permit2Contract),
            abi.encodeWithSelector(
                IBatchPermit.permitWitnessTransferFrom.selector,
                permit2.permit,
                transferDetails,
                owner,
                witness.witnessHash,
                witness.witnessTypeString,
                permit2.signature
            )
        );
        vm.expectCall(token, abi.encodeWithSelector(ERC20.transferFrom.selector, owner, tokenRecipient, amount));
        target.initiatePermit2(tokenRecipient, outputs, permit2);
    }

    // input multiple ERC20s
    function test_initiatePermit2_multi() public {
        // construct transfer details
        transferDetails.push(ISignatureTransfer.SignatureTransferDetails({to: tokenRecipient, requestedAmount: amount}));

        // setup second token
        address token2 = address(new TestERC20("bye", "BYE"));
        TestERC20(token2).mint(owner, amount * 10000);
        vm.prank(owner);
        TestERC20(token2).approve(address(permit2Contract), amount * 10000);

        // add second token input
        inputs.push(IOrders.Input(token2, amount * 2));

        // add TokenPermissions
        permit2.permit.permitted.push(ISignatureTransfer.TokenPermissions({token: token2, amount: amount * 2}));

        // add TransferDetails
        transferDetails.push(
            ISignatureTransfer.SignatureTransferDetails({to: tokenRecipient, requestedAmount: amount * 2})
        );

        // re-sign new permit
        permit2.signature = signPermit(ownerKey, address(target), permit2.permit, witness);

        // expect Order event is emitted, ERC20 is transferred
        vm.expectEmit();
        emit Order(permit2.permit.deadline, inputs, outputs);
        vm.expectCall(
            address(permit2Contract),
            abi.encodeWithSelector(
                IBatchPermit.permitWitnessTransferFrom.selector,
                permit2.permit,
                transferDetails,
                owner,
                witness.witnessHash,
                witness.witnessTypeString,
                permit2.signature
            )
        );
        vm.expectCall(token, abi.encodeWithSelector(ERC20.transferFrom.selector, owner, tokenRecipient, amount));
        vm.expectCall(token2, abi.encodeWithSelector(ERC20.transferFrom.selector, owner, tokenRecipient, amount * 2));
        target.initiatePermit2(tokenRecipient, outputs, permit2);
    }

    function test_fillPermit2() public {
        // construct transfer details
        transferDetails.push(ISignatureTransfer.SignatureTransferDetails({to: recipient, requestedAmount: amount}));

        vm.expectEmit();
        emit Filled(outputs);
        vm.expectCall(
            address(permit2Contract),
            abi.encodeWithSelector(
                IBatchPermit.permitWitnessTransferFrom.selector,
                permit2.permit,
                transferDetails,
                owner,
                witness.witnessHash,
                witness.witnessTypeString,
                permit2.signature
            )
        );
        vm.expectCall(token, abi.encodeWithSelector(ERC20.transferFrom.selector, owner, recipient, amount));
        target.fillPermit2(outputs, permit2);
    }

    function test_fillPermit2_multi() public {
        // construct transfer details
        transferDetails.push(ISignatureTransfer.SignatureTransferDetails({to: recipient, requestedAmount: amount}));

        // setup second token
        address token2 = address(new TestERC20("bye", "BYE"));
        TestERC20(token2).mint(owner, amount * 10000);
        vm.prank(owner);
        TestERC20(token2).approve(address(permit2Contract), amount * 10000);

        // add second token output
        outputs.push(IOrders.Output(token2, amount * 2, recipient, chainId));

        // add TokenPermissions
        permit2.permit.permitted.push(ISignatureTransfer.TokenPermissions({token: token2, amount: amount * 2}));

        // add TransferDetails
        transferDetails.push(ISignatureTransfer.SignatureTransferDetails({to: recipient, requestedAmount: amount * 2}));

        // re-sign new permit
        witness = target.outputWitness(outputs);
        permit2.signature = signPermit(ownerKey, address(target), permit2.permit, witness);

        // expect Filled event is emitted, ERC20 is transferred
        vm.expectEmit();
        emit Filled(outputs);
        vm.expectCall(
            address(permit2Contract),
            abi.encodeWithSelector(
                IBatchPermit.permitWitnessTransferFrom.selector,
                permit2.permit,
                transferDetails,
                owner,
                witness.witnessHash,
                witness.witnessTypeString,
                permit2.signature
            )
        );
        vm.expectCall(token, abi.encodeWithSelector(ERC20.transferFrom.selector, owner, recipient, amount));
        vm.expectCall(token2, abi.encodeWithSelector(ERC20.transferFrom.selector, owner, recipient, amount * 2));
        target.fillPermit2(outputs, permit2);
    }
}
