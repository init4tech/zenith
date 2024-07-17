// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ISignatureTransfer} from "./vendored/ISignatureTransfer.sol";
import {IOrders} from "./IOrders.sol";

/// @param permit - the permit2 batch token transfer details. includes a `deadline` and an unordered `nonce`.
/// @param signer - the signer of the permit2 info; the owner of the tokens.
/// @param signature - the signature over the permit + witness.
struct Permit2Batch {
    ISignatureTransfer.PermitBatchTransferFrom permit;
    address owner;
    bytes signature;
}

/// @param permit - the permit2 single token transfer details. includes a `deadline` and an unordered `nonce`.
/// @param signer - the signer of the permit2 info; the owner of the tokens.
/// @param signature - the signature over the permit + witness.
struct Permit2 {
    ISignatureTransfer.PermitTransferFrom permit;
    address owner;
    bytes signature;
}

abstract contract UsesPermit2 {
    string constant _OUTPUT_WITNESS_TYPESTRING =
        "Output[] outputs)Output(address token,uint256 amount,address recipient,uint32 chainId)TokenPermissions(address token,uint256 amount)";

    bytes32 constant _OUTPUT_TYPEHASH =
        keccak256("Output(address token,uint256 amount,address recipient,uint32 chainId)");

    string constant _WITNESS_TYPESTRING = "bytes32 witness)TokenPermissions(address token,uint256 amount)";

    /// @notice Thrown when a signed Output does not match the corresponding TokenPermissions.
    error OutputMismatch();

    /// @notice The Permit2 contract address.
    address immutable permit2Contract;

    constructor(address _permit2) {
        permit2Contract = _permit2;
    }

    /// @notice Transfer a batch of tokens using permit2.
    /// @param outputs - the Outputs for the witness field.
    /// @param transferDetails - the TokenPermissions for the transfer, generated based on the use-case (see `_initiateTransferDetails` and `_fillTransferDetails`).
    /// @param permit2 - the Permit2Batch information.
    function _permitWitnessTransferFrom(
        IOrders.Output[] memory outputs,
        ISignatureTransfer.SignatureTransferDetails[] memory transferDetails,
        Permit2Batch calldata permit2
    ) internal {
        ISignatureTransfer(permit2Contract).permitWitnessTransferFrom(
            permit2.permit,
            transferDetails,
            permit2.owner,
            _witness(outputs),
            _OUTPUT_WITNESS_TYPESTRING,
            permit2.signature
        );
    }

    /// @notice Transfer tokens using permit2.
    /// @param witness - the pre-hashed witness field.
    /// @param permit2 - the Permit2 information.
    function _permitWitnessTransferFrom(bytes32 witness, Permit2 calldata permit2) internal {
        ISignatureTransfer(permit2Contract).permitWitnessTransferFrom(
            permit2.permit,
            _passageTransferDetails(permit2.permit.permitted),
            permit2.owner,
            witness,
            _WITNESS_TYPESTRING,
            permit2.signature
        );
    }

    /// @notice Encode the Output array according to EIP-712 for use as a permit2 witness.
    /// @param outputs - the Outputs to encode.
    /// @return witness - the encoded witness field.
    function _witness(IOrders.Output[] memory outputs) internal pure returns (bytes32 witness) {
        uint256 num = outputs.length;
        bytes32[] memory hashes = new bytes32[](num);
        for (uint256 i = 0; i < num; ++i) {
            hashes[i] = keccak256(abi.encode(_OUTPUT_TYPEHASH, outputs[i]));
        }
        witness = keccak256(abi.encodePacked(hashes));
    }

    /// @notice Encode & hash the rollupChainId and rollupRecipient for use as a permit2 witness.
    /// @return witness - the encoded witness field.
    function _witness(uint256 rollupChainId, address rollupRecipient) internal pure returns (bytes32 witness) {
        witness = keccak256(abi.encode(rollupChainId, rollupRecipient));
    }

    /// @notice Hash the hostRecipient for use as a permit2 witness.
    /// @return witness - the encoded witness field.
    function _witness(address hostRecipient) internal pure returns (bytes32 witness) {
        witness = keccak256(abi.encode(hostRecipient));
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

    /// @notice transform TokenPermissions to TransferDetails, for passing to permit2.
    /// @dev always transfers the full permitted amount to address(this).
    /// @param permitted - the TokenPermissions to transform.
    /// @return transferDetails - the SignatureTransferDetails generated.
    function _passageTransferDetails(ISignatureTransfer.TokenPermissions calldata permitted)
        internal
        view
        returns (ISignatureTransfer.SignatureTransferDetails memory transferDetails)
    {
        transferDetails.to = address(this);
        transferDetails.requestedAmount = permitted.amount;
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
