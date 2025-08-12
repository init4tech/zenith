// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.26;

// test contracts
import {RollupOrders} from "../../src/orders/RollupOrders.sol";
import {IOrders} from "../../src/orders/IOrders.sol";
import {UsesPermit2} from "../../src/UsesPermit2.sol";
// utils
import {Permit2Helpers, IBatchPermit, TestERC20} from "../Helpers.t.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Test, console2} from "forge-std/Test.sol";

contract OrderOriginPermit2Test is Permit2Helpers {
    RollupOrders public target;

    IOrders.Input[] public inputs;
    IOrders.Output[] public outputs;

    address token;
    address recipient = address(0xdeadbeef);
    uint256 amount = 200;
    uint256 deadline;

    event Order(uint256 deadline, IOrders.Input[] inputs, IOrders.Output[] outputs);

    event Filled(IOrders.Output[] outputs);

    function setUp() public virtual {
        // setup Orders contract
        target = ROLLUP_ORDERS;
        vm.label(address(target), "orders");
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
        batchPermit.permit.nonce = 0;
        batchPermit.permit.deadline = block.timestamp;
        batchPermit.owner = owner;
        batchPermit.permit.permitted.push(ISignatureTransfer.TokenPermissions({token: token, amount: amount}));
        batchTransferDetails.push(ISignatureTransfer.SignatureTransferDetails({to: recipient, requestedAmount: amount}));

        // setup Order Inputs/Outputs
        IOrders.Input memory input = IOrders.Input(token, amount);
        inputs.push(input);

        IOrders.Output memory output = IOrders.Output(token, amount, recipient, ROLLUP_CHAIN_ID);
        outputs.push(output);

        deadline = block.timestamp;

        // construct Orders witness
        witness = target.outputWitness(outputs);

        // sign permit + witness
        batchPermit.signature = signPermit(ownerKey, address(target), batchPermit.permit, witness);
    }

    function test_initiatePermit2() public {
        // expect Order event is initiated, ERC20 is transferred
        vm.expectEmit();
        emit Order(batchPermit.permit.deadline, inputs, outputs);
        vm.expectCall(
            address(PERMIT2),
            abi.encodeWithSelector(
                IBatchPermit.permitWitnessTransferFrom.selector,
                batchPermit.permit,
                batchTransferDetails,
                owner,
                witness.witnessHash,
                witness.witnessTypeString,
                batchPermit.signature
            )
        );
        vm.expectCall(token, abi.encodeWithSelector(ERC20.transferFrom.selector, owner, recipient, amount));
        target.initiatePermit2(recipient, outputs, batchPermit);
    }

    // input multiple ERC20s
    function test_initiatePermit2_multi() public {
        // setup second token
        address token2 = address(ROLLUP_WETH);
        // mint tokens to owner
        vm.prank(ROLLUP_MINTER);
        TestERC20(token2).mint(owner, amount * 10000);
        // approve permit2 from owner
        vm.prank(owner);
        TestERC20(token2).approve(address(PERMIT2), amount * 10000);

        // add second token to Inputs, TokenPermissions, and TransferDetails
        inputs.push(IOrders.Input(token2, amount));
        batchPermit.permit.permitted.push(ISignatureTransfer.TokenPermissions({token: token2, amount: amount}));
        batchTransferDetails.push(ISignatureTransfer.SignatureTransferDetails({to: recipient, requestedAmount: amount}));

        // re-sign new permit (witness is the same because Outputs haven't changed)
        batchPermit.signature = signPermit(ownerKey, address(target), batchPermit.permit, witness);

        // expect Order event is emitted, ERC20 is transferred
        vm.expectEmit();
        emit Order(batchPermit.permit.deadline, inputs, outputs);
        vm.expectCall(
            address(PERMIT2),
            abi.encodeWithSelector(
                IBatchPermit.permitWitnessTransferFrom.selector,
                batchPermit.permit,
                batchTransferDetails,
                owner,
                witness.witnessHash,
                witness.witnessTypeString,
                batchPermit.signature
            )
        );
        vm.expectCall(token, abi.encodeWithSelector(ERC20.transferFrom.selector, owner, recipient, amount));
        vm.expectCall(token2, abi.encodeWithSelector(ERC20.transferFrom.selector, owner, recipient, amount));
        target.initiatePermit2(recipient, outputs, batchPermit);
    }

    function test_fillPermit2() public {
        vm.expectEmit();
        emit Filled(outputs);
        vm.expectCall(
            address(PERMIT2),
            abi.encodeWithSelector(
                IBatchPermit.permitWitnessTransferFrom.selector,
                batchPermit.permit,
                batchTransferDetails,
                owner,
                witness.witnessHash,
                witness.witnessTypeString,
                batchPermit.signature
            )
        );
        vm.expectCall(token, abi.encodeWithSelector(ERC20.transferFrom.selector, owner, recipient, amount));
        target.fillPermit2(outputs, batchPermit);
    }

    function test_fillPermit2_multi() public {
        // setup second token
        address token2 = address(ROLLUP_WETH);
        // mint tokens to owner
        vm.prank(ROLLUP_MINTER);
        TestERC20(token2).mint(owner, amount * 10000);
        // approve permit2 from owner
        vm.prank(owner);
        TestERC20(token2).approve(address(PERMIT2), amount * 10000);

        // add second token to Outputs, TokenPermissions, and TransferDetails
        outputs.push(IOrders.Output(token2, amount, recipient, ROLLUP_CHAIN_ID));
        batchPermit.permit.permitted.push(ISignatureTransfer.TokenPermissions({token: token2, amount: amount}));
        batchTransferDetails.push(ISignatureTransfer.SignatureTransferDetails({to: recipient, requestedAmount: amount}));

        // re-sign new permit
        witness = target.outputWitness(outputs);
        batchPermit.signature = signPermit(ownerKey, address(target), batchPermit.permit, witness);

        // expect Filled event is emitted, ERC20 is transferred
        vm.expectEmit();
        emit Filled(outputs);
        vm.expectCall(
            address(PERMIT2),
            abi.encodeWithSelector(
                IBatchPermit.permitWitnessTransferFrom.selector,
                batchPermit.permit,
                batchTransferDetails,
                owner,
                witness.witnessHash,
                witness.witnessTypeString,
                batchPermit.signature
            )
        );
        vm.expectCall(token, abi.encodeWithSelector(ERC20.transferFrom.selector, owner, recipient, amount));
        vm.expectCall(token2, abi.encodeWithSelector(ERC20.transferFrom.selector, owner, recipient, amount));
        target.fillPermit2(outputs, batchPermit);
    }
}
