// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {UsesPermit2} from "../UsesPermit2.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";

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
