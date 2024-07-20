// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IOrders} from "./orders/IOrders.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";

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
