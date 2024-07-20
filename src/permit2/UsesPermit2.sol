// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {IOrders} from "../interfaces/IOrders.sol";

abstract contract UsesPermit2 {
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

    /// @notice Struct to hold the pre-hashed witness field and the witness type string.
    struct Witness {
        bytes32 witnessHash;
        string witnessTypeString;
    }

    /// @notice The Permit2 contract address.
    address immutable permit2Contract;

    constructor(address _permit2) {
        permit2Contract = _permit2;
    }
}

abstract contract OrdersPermit2 is UsesPermit2 {
    string constant _OUTPUT_WITNESS_TYPESTRING =
        "Output[] outputs)Output(address token,uint256 amount,address recipient,uint32 chainId)TokenPermissions(address token,uint256 amount)";

    bytes32 constant _OUTPUT_TYPEHASH =
        keccak256("Output(address token,uint256 amount,address recipient,uint32 chainId)");

    /// @notice Thrown when a signed Output does not match the corresponding TokenPermissions.
    error OutputMismatch();

    /// @notice Encode the Output array according to EIP-712 for use as a permit2 witness.
    /// @param outputs - the Outputs to encode.
    /// @return _witness - the encoded witness field.
    function outputWitness(IOrders.Output[] memory outputs) public pure returns (Witness memory _witness) {
        uint256 num = outputs.length;
        bytes32[] memory hashes = new bytes32[](num);
        for (uint256 i = 0; i < num; ++i) {
            hashes[i] = keccak256(abi.encode(_OUTPUT_TYPEHASH, outputs[i]));
        }
        _witness.witnessHash = keccak256(abi.encodePacked(hashes));
        _witness.witnessTypeString = _OUTPUT_WITNESS_TYPESTRING;
    }

    /// @notice Transfer a batch of tokens using permit2.
    /// @param _witness - the hashed witness and its typestring.
    /// @param transferDetails - the TokenPermissions for the transfer, generated based on the use-case (see `_initiateTransferDetails` and `_fillTransferDetails`).
    /// @param permit2 - the Permit2Batch information.
    function _permitWitnessTransferFrom(
        Witness memory _witness,
        ISignatureTransfer.SignatureTransferDetails[] memory transferDetails,
        Permit2Batch calldata permit2
    ) internal {
        ISignatureTransfer(permit2Contract).permitWitnessTransferFrom(
            permit2.permit,
            transferDetails,
            permit2.owner,
            _witness.witnessHash,
            _witness.witnessTypeString,
            permit2.signature
        );
    }

    /// @notice transform Output and TokenPermissions structs to TransferDetails structs, for passing to permit2.
    /// @dev always transfers the full permitted amount.
    /// @param outputs - the Outputs to transform.
    /// @param permitted - the TokenPermissions to transform.
    /// @return transferDetails - the SignatureTransferDetails generated.
    function _fillTransferDetails(
        IOrders.Output[] memory outputs,
        ISignatureTransfer.TokenPermissions[] calldata permitted
    ) internal pure returns (ISignatureTransfer.SignatureTransferDetails[] memory transferDetails) {
        if (permitted.length != outputs.length) revert ISignatureTransfer.LengthMismatch();
        transferDetails = new ISignatureTransfer.SignatureTransferDetails[](permitted.length);
        for (uint256 i; i < permitted.length; i++) {
            if (permitted[i].token != outputs[i].token) revert OutputMismatch();
            if (permitted[i].amount != outputs[i].amount) revert OutputMismatch();
            transferDetails[i] = ISignatureTransfer.SignatureTransferDetails(outputs[i].recipient, outputs[i].amount);
        }
    }

    /// @notice transform TokenPermissions structs to TransferDetails structs, for passing to permit2.
    /// @dev always transfers the full permitted amount.
    /// @param tokenRecipient - recipient of all the permitted tokens.
    /// @param permitted - the TokenPermissions to transform.
    /// @return transferDetails - the SignatureTransferDetails generated.
    function _initiateTransferDetails(address tokenRecipient, ISignatureTransfer.TokenPermissions[] calldata permitted)
        internal
        pure
        returns (ISignatureTransfer.SignatureTransferDetails[] memory transferDetails)
    {
        transferDetails = new ISignatureTransfer.SignatureTransferDetails[](permitted.length);
        for (uint256 i; i < permitted.length; i++) {
            transferDetails[i] = ISignatureTransfer.SignatureTransferDetails(tokenRecipient, permitted[i].amount);
        }
    }

    /// @notice transform permit2 TokenPermissions to Inputs structs, for emitting.
    /// @dev TokenPermissions and Inputs structs contain identical fields - (address token, uint256 amount).
    /// @param permitted - the TokenPermissions to transform.
    /// @return inputs - the Inputs generated.
    function _inputs(ISignatureTransfer.TokenPermissions[] calldata permitted)
        internal
        pure
        returns (IOrders.Input[] memory inputs)
    {
        inputs = new IOrders.Input[](permitted.length);
        for (uint256 i; i < permitted.length; i++) {
            inputs[i] = IOrders.Input(permitted[i].token, permitted[i].amount);
        }
    }
}

abstract contract PassagePermit2 is UsesPermit2 {
    string constant _ENTER_WITNESS_TYPESTRING =
        "EnterWitness witness)EnterWitness(uint256 rollupChainId,address rollupRecipient)TokenPermissions(address token,uint256 amount)";

    bytes32 constant _ENTER_WITNESS_TYPEHASH = keccak256("EnterWitness(uint256 rollupChainId,address rollupRecipient)");

    string constant _EXIT_WITNESS_TYPESTRING =
        "ExitWitness witness)ExitWitness(address hostRecipient)TokenPermissions(address token,uint256 amount)";

    bytes32 constant _EXIT_WITNESS_TYPEHASH = keccak256("ExitWitness(address hostRecipient)");

    /// @notice Struct to hash Enter witness data into a 32-byte witness field, in an EIP-712 compliant way.
    struct EnterWitness {
        uint256 rollupChainId;
        address rollupRecipient;
    }

    /// @notice Struct to hash Exit witness data into a 32-byte witness field, in an EIP-712 compliant way.
    struct ExitWitness {
        address hostRecipient;
    }

    /// @notice Encode & hash the rollupChainId and rollupRecipient for use as a permit2 witness.
    /// @return _witness - the hashed witness and its typestring.
    function enterWitness(uint256 rollupChainId, address rollupRecipient)
        public
        pure
        returns (Witness memory _witness)
    {
        _witness.witnessHash =
            keccak256(abi.encode(_ENTER_WITNESS_TYPEHASH, EnterWitness(rollupChainId, rollupRecipient)));
        _witness.witnessTypeString = _ENTER_WITNESS_TYPESTRING;
    }

    /// @notice Hash the hostRecipient for use as a permit2 witness.
    /// @return _witness - the hashed witness and its typestring.
    function exitWitness(address hostRecipient) public pure returns (Witness memory _witness) {
        _witness.witnessHash = keccak256(abi.encode(_EXIT_WITNESS_TYPEHASH, ExitWitness(hostRecipient)));
        _witness.witnessTypeString = _EXIT_WITNESS_TYPESTRING;
    }

    /// @notice Transfer tokens using permit2.
    /// @param _witness - the hashed witness and its typestring.
    /// @param permit2 - the Permit2 information.
    function _permitWitnessTransferFrom(Witness memory _witness, Permit2 calldata permit2) internal {
        ISignatureTransfer(permit2Contract).permitWitnessTransferFrom(
            permit2.permit,
            _selfTransferDetails(permit2.permit.permitted.amount),
            permit2.owner,
            _witness.witnessHash,
            _witness.witnessTypeString,
            permit2.signature
        );
    }

    /// @notice Construct TransferDetails transferring a balance to this contract, for passing to permit2.
    /// @dev always transfers the full amount to address(this).
    /// @param amount - the amount to transfer to this contract.
    /// @return transferDetails - the SignatureTransferDetails generated.
    function _selfTransferDetails(uint256 amount)
        internal
        view
        returns (ISignatureTransfer.SignatureTransferDetails memory transferDetails)
    {
        transferDetails.to = address(this);
        transferDetails.requestedAmount = amount;
    }
}
