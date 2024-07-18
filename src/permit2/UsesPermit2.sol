// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {HostOrders, RollupOrders, Input, Output} from "../Orders.sol";
import {Passage, RollupPassage} from "../Passage.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

abstract contract UsesPermit2 {
    /// @notice The Permit2 contract address.
    address immutable permit2Contract;

    constructor(address _permit2) {
        permit2Contract = _permit2;
    }
}

abstract contract Permit2Helper is UsesPermit2 {
    RollupOrders constant ruOrders = RollupOrders(address(0));
    HostOrders constant hostOrders = HostOrders(address(0));
    Passage constant passage = Passage(payable(address(0)));
    RollupPassage constant ruPassage = RollupPassage(payable(address(0)));

    string constant _OUTPUT_WITNESS_TYPESTRING =
        "Output[] outputs)Output(address token,uint256 amount,address recipient,uint32 chainId)TokenPermissions(address token,uint256 amount)";

    bytes32 constant _OUTPUT_TYPEHASH =
        keccak256("Output(address token,uint256 amount,address recipient,uint32 chainId)");

    string constant _ENTER_WITNESS_TYPESTRING =
        "EnterWitness witness)EnterWitness(uint256 rollupChainId,address rollupRecipient)TokenPermissions(address token,uint256 amount)";

    bytes32 constant _ENTER_WITNESS_TYPEHASH = keccak256("EnterWitness(uint256 rollupChainId,address rollupRecipient)");

    string constant _EXIT_WITNESS_TYPESTRING =
        "ExitWitness witness)ExitWitness(address hostRecipient)TokenPermissions(address token,uint256 amount)";

    bytes32 constant _EXIT_WITNESS_TYPEHASH = keccak256("ExitWitness(address hostRecipient)");

    enum Typestring {
        Output,
        Enter,
        Exit
    }

    /// @notice Struct to hash Enter witness data into a 32-byte witness field, in an EIP-712 compliant way.
    struct EnterWitness {
        uint256 rollupChainId;
        address rollupRecipient;
    }

    /// @notice Struct to hash Exit witness data into a 32-byte witness field, in an EIP-712 compliant way.
    struct ExitWitness {
        address hostRecipient;
    }

    /// @param permit - the permit2 single token transfer details. includes a `deadline` and an unordered `nonce`.
    /// @param signer - the signer of the permit2 info; the owner of the tokens.
    /// @param signature - the signature over the permit + witness.
    struct Permit2 {
        ISignatureTransfer.PermitTransferFrom permit;
        address owner;
        bytes signature;
    }

    /// @param permit - the permit2 batch token transfer details. includes a `deadline` and an unordered `nonce`.
    /// @param signer - the signer of the permit2 info; the owner of the tokens.
    /// @param signature - the signature over the permit + witness.
    struct Permit2Batch {
        ISignatureTransfer.PermitBatchTransferFrom permit;
        address owner;
        bytes signature;
    }

    /// @notice Initiate an Order, transferring Input tokens to the Filler via permit2 signed batch transfer.
    /// @dev Can only provide ERC20 tokens as Inputs.
    /// @dev the permit2 signer is the swapper providing the Input tokens in exchange for the Outputs.
    /// @dev Filler MUST submit `fill` and `intitiate` within an atomic bundle.
    /// @dev NOTE that here, Output.chainId denotes the *target* chainId.
    /// @param tokenRecipient - the recipient of the Input tokens, provided by msg.sender (un-verified by permit2).
    /// @param outputs - the Outputs required in exchange for the Input tokens. signed over via permit2 witness.
    /// @param permit2 - the permit2 details, signer, and signature.
    function initiatePermit2(address tokenRecipient, Output[] memory outputs, Permit2Batch calldata permit2) external {
        // transfer all tokens to this contract via permit2
        _permitWitnessTransferFrom(_outputWitness(outputs), Typestring.Output, permit2);

        // allow tokens
        _allow(address(ruOrders), permit2.permit.permitted);

        // initiate the Order
        ruOrders.initiate(permit2.permit.deadline, _inputs(permit2.permit.permitted), outputs);

        // sweep the inputs to the tokenRecipient
        for (uint256 i = 0; i < permit2.permit.permitted.length; i++) {
            ruOrders.sweep(tokenRecipient, permit2.permit.permitted[i].token);
        }
    }

    /// @notice Allows ERC20 tokens to exit the rollup.
    /// @param hostRecipient - The *requested* recipient of tokens on the host chain.
    /// @param permit2 - The Permit2 information, including token & amount.
    /// @custom:emits ExitToken
    function exitTokenPermit2(address hostRecipient, Permit2 calldata permit2) public {
        // transfer tokens to this contract
        _permitWitnessTransferFrom(_exitWitness(hostRecipient), Typestring.Exit, permit2);

        // allow tokens
        _allow(address(ruPassage), permit2.permit.permitted);

        // exit
        ruPassage.exitToken(hostRecipient, permit2.permit.permitted.token, permit2.permit.permitted.amount);
    }

    /// @notice Fill any number of Order(s), by transferring their Output(s) via permit2 signed batch transfer.
    /// @dev Can only provide ERC20 tokens as Outputs.
    /// @dev Filler may aggregate multiple Outputs with the same (`chainId`, `recipient`, `token`) into a single Output with the summed `amount`.
    /// @dev the permit2 signer is the Filler providing the Outputs.
    /// @dev the permit2 `permitted` tokens MUST match provided Outputs.
    /// @dev Filler MUST submit `fill` and `intitiate` within an atomic bundle.
    /// @dev NOTE that here, Output.chainId denotes the *origin* chainId.
    /// @param outputs - The Outputs to be transferred. signed over via permit2 witness.
    /// @param permit2 - the permit2 details, signer, and signature.
    /// @custom:emits Filled
    function fillPermit2(Output[] memory outputs, Permit2Batch calldata permit2) external {
        // transfer all tokens to the Output recipients via permit2 (includes check on nonce & deadline)
        _permitWitnessTransferFrom(_outputWitness(outputs), Typestring.Output, permit2);

        // allow tokens
        _allow(address(hostOrders), permit2.permit.permitted);

        // fill the orders
        hostOrders.fill(outputs);
    }

    /// @notice Allows ERC20 tokens to enter the rollup.
    /// @param rollupChainId - The rollup chain to enter.
    /// @param rollupRecipient - The recipient of tokens on the rollup.
    /// @param permit2 - The Permit2 information, including token & amount.
    function enterTokenPermit2(uint256 rollupChainId, address rollupRecipient, Permit2 calldata permit2) public {
        // transfer tokens to this contract via permit2
        _permitWitnessTransferFrom(_enterWitness(rollupChainId, rollupRecipient), Typestring.Enter, permit2);

        // allow tokens
        _allow(address(passage), permit2.permit.permitted);

        // enter
        passage.enterToken(
            rollupChainId, rollupRecipient, permit2.permit.permitted.token, permit2.permit.permitted.amount
        );
    }

    /// @notice Transfer a batch of tokens using permit2.
    /// @param witness - the pre-hashed witness field.
    /// @param permit2 - the Permit2Batch information.
    function _permitWitnessTransferFrom(bytes32 witness, Typestring typestr, Permit2Batch calldata permit2) internal {
        ISignatureTransfer(permit2Contract).permitWitnessTransferFrom(
            permit2.permit,
            _batchTransferDetails(permit2.permit.permitted),
            permit2.owner,
            witness,
            _typestring(typestr),
            permit2.signature
        );
    }

    /// @notice Transfer tokens using permit2.
    /// @param witness - the pre-hashed witness field.
    /// @param permit2 - the Permit2 information.
    function _permitWitnessTransferFrom(bytes32 witness, Typestring typestr, Permit2 calldata permit2) internal {
        ISignatureTransfer(permit2Contract).permitWitnessTransferFrom(
            permit2.permit,
            _singleTransferDetails(permit2.permit.permitted),
            permit2.owner,
            witness,
            _typestring(typestr),
            permit2.signature
        );
    }

    function _allow(address spender, ISignatureTransfer.TokenPermissions[] calldata permitted) internal {
        for (uint256 i = 0; i < permitted.length; i++) {
            _allow(spender, permitted[i]);
        }
    }

    function _allow(address spender, ISignatureTransfer.TokenPermissions calldata permitted) internal {
        if (IERC20(permitted.token).allowance(address(this), spender) < permitted.amount) {
            IERC20(permitted.token).approve(spender, type(uint256).max);
        }
    }

    function _typestring(Typestring typestr) internal pure returns (string memory) {
        if (typestr == Typestring.Output) return _OUTPUT_WITNESS_TYPESTRING;
        if (typestr == Typestring.Enter) return _ENTER_WITNESS_TYPESTRING;
        if (typestr == Typestring.Exit) return _EXIT_WITNESS_TYPESTRING;
        revert();
    }

    /// @notice transform TokenPermissions structs to TransferDetails structs, for passing to permit2.
    /// @dev always transfers the full permitted amount to address(this).
    /// @param permitted - the TokenPermissions to transform.
    /// @return transferDetails - the SignatureTransferDetails generated.
    function _batchTransferDetails(ISignatureTransfer.TokenPermissions[] calldata permitted)
        internal
        view
        returns (ISignatureTransfer.SignatureTransferDetails[] memory transferDetails)
    {
        transferDetails = new ISignatureTransfer.SignatureTransferDetails[](permitted.length);
        for (uint256 i; i < permitted.length; i++) {
            transferDetails[i] = _singleTransferDetails(permitted[i]);
        }
    }

    /// @notice transform TokenPermissions to TransferDetails, for passing to permit2.
    /// @dev always transfers the full permitted amount to address(this).
    /// @param permitted - the TokenPermissions to transform.
    /// @return transferDetails - the SignatureTransferDetails generated.
    function _singleTransferDetails(ISignatureTransfer.TokenPermissions calldata permitted)
        internal
        view
        returns (ISignatureTransfer.SignatureTransferDetails memory transferDetails)
    {
        transferDetails.to = address(this);
        transferDetails.requestedAmount = permitted.amount;
    }

    /// @notice Encode the Output array according to EIP-712 for use as a permit2 witness.
    /// @param outputs - the Outputs to encode.
    /// @return witness - the encoded witness field.
    function _outputWitness(Output[] memory outputs) internal pure returns (bytes32 witness) {
        uint256 num = outputs.length;
        bytes32[] memory hashes = new bytes32[](num);
        for (uint256 i = 0; i < num; ++i) {
            hashes[i] = keccak256(abi.encode(_OUTPUT_TYPEHASH, outputs[i]));
        }
        witness = keccak256(abi.encodePacked(hashes));
    }

    /// @notice Encode & hash the rollupChainId and rollupRecipient for use as a permit2 witness.
    /// @return witness - the encoded witness field.
    function _enterWitness(uint256 rollupChainId, address rollupRecipient) internal pure returns (bytes32 witness) {
        witness = keccak256(abi.encode(_ENTER_WITNESS_TYPEHASH, EnterWitness(rollupChainId, rollupRecipient)));
    }

    /// @notice Hash the hostRecipient for use as a permit2 witness.
    /// @return witness - the encoded witness field.
    function _exitWitness(address hostRecipient) internal pure returns (bytes32 witness) {
        witness = keccak256(abi.encode(_EXIT_WITNESS_TYPEHASH, ExitWitness(hostRecipient)));
    }

    /// @notice transform permit2 TokenPermissions to Inputs structs, for emitting.
    /// @dev TokenPermissions and Inputs structs contain identical fields - (address token, uint256 amount).
    /// @param permitted - the TokenPermissions to transform.
    /// @return inputs - the Inputs generated.
    function _inputs(ISignatureTransfer.TokenPermissions[] calldata permitted)
        internal
        pure
        returns (Input[] memory inputs)
    {
        inputs = new Input[](permitted.length);
        for (uint256 i; i < permitted.length; i++) {
            inputs[i] = Input(permitted[i].token, permitted[i].amount);
        }
    }
}
