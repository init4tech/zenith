// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Zenith} from "../src/Zenith.sol";
import {UsesPermit2} from "../src/permit2/UsesPermit2.sol";

import {Test, console2} from "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";

contract TestERC20 is ERC20Burnable {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }
}

contract Permit2Stub {
    /// @notice stubbed `permitWitnessTransferFrom` - does not check signature, nonce, or deadline
    function permitWitnessTransferFrom(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes32, /*witness*/
        string calldata, /*witnessTypeString*/
        bytes calldata /*signature*/
    ) external {
        ERC20(permit.permitted.token).transferFrom(owner, transferDetails.to, transferDetails.requestedAmount);
    }
}

contract BatchPermit2Stub {
    function permitWitnessTransferFrom(
        ISignatureTransfer.PermitBatchTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails[] calldata transferDetails,
        address owner,
        bytes32, /*witness*/
        string calldata, /*witnessTypeString*/
        bytes calldata /*signature*/
    ) external {
        for (uint256 i = 0; i < transferDetails.length; i++) {
            ERC20(permit.permitted[i].token).transferFrom(
                owner, transferDetails[i].to, transferDetails[i].requestedAmount
            );
        }
    }
}

contract Permit2Helpers is Test {
    string public constant _PERMIT_TRANSFER_FROM_WITNESS_TYPEHASH_STUB =
        "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,";

    bytes32 public constant _TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

    string public constant _PERMIT_BATCH_WITNESS_TRANSFER_FROM_TYPEHASH_STUB =
        "PermitBatchWitnessTransferFrom(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline,";

    /// @notice given a Permit and a Witness, produce a signature from the `owner`
    function signPermit(
        uint256 signingKey,
        address spender,
        ISignatureTransfer.PermitTransferFrom memory permit,
        UsesPermit2.Witness memory _witness
    ) internal pure returns (bytes memory signature) {
        bytes32 permit2Hash = hashWithWitness(spender, permit, _witness.witnessHash, _witness.witnessTypeString);
        uint8 v;
        bytes32 r;
        bytes32 s;
        (v, r, s) = vm.sign(signingKey, permit2Hash);
        signature = abi.encodePacked(r, s, v);
    }

    // this function is private on permit2 contracts but need to port it here for test functionality
    function hashWithWitness(
        address spender,
        ISignatureTransfer.PermitTransferFrom memory _permit,
        bytes32 witness,
        string memory witnessTypeString
    ) internal pure returns (bytes32) {
        bytes32 typeHash = keccak256(abi.encodePacked(_PERMIT_TRANSFER_FROM_WITNESS_TYPEHASH_STUB, witnessTypeString));

        bytes32 tokenPermissionsHash = _hashTokenPermissions(_permit.permitted);
        return keccak256(abi.encode(typeHash, tokenPermissionsHash, spender, _permit.nonce, _permit.deadline, witness));
    }

    /// @notice given a Permit and a Witness, produce a signature from the `owner`
    function signPermit(
        uint256 signingKey,
        address spender,
        ISignatureTransfer.PermitBatchTransferFrom memory permit,
        UsesPermit2.Witness memory _witness
    ) internal pure returns (bytes memory signature) {
        bytes32 permit2Hash = hashWithWitness(spender, permit, _witness.witnessHash, _witness.witnessTypeString);
        uint8 v;
        bytes32 r;
        bytes32 s;
        (v, r, s) = vm.sign(signingKey, permit2Hash);
        signature = abi.encodePacked(r, s, v);
    }

    function hashWithWitness(
        address spender,
        ISignatureTransfer.PermitBatchTransferFrom memory permit,
        bytes32 witness,
        string memory witnessTypeString
    ) internal pure returns (bytes32) {
        bytes32 typeHash =
            keccak256(abi.encodePacked(_PERMIT_BATCH_WITNESS_TRANSFER_FROM_TYPEHASH_STUB, witnessTypeString));

        uint256 numPermitted = permit.permitted.length;
        bytes32[] memory tokenPermissionHashes = new bytes32[](numPermitted);

        for (uint256 i = 0; i < numPermitted; ++i) {
            tokenPermissionHashes[i] = _hashTokenPermissions(permit.permitted[i]);
        }

        return keccak256(
            abi.encode(
                typeHash,
                keccak256(abi.encodePacked(tokenPermissionHashes)),
                spender,
                permit.nonce,
                permit.deadline,
                witness
            )
        );
    }

    // this function is private on permit2 contracts but need to port it here for test functionality
    function _hashTokenPermissions(ISignatureTransfer.TokenPermissions memory _permitted)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(_TOKEN_PERMISSIONS_TYPEHASH, _permitted));
    }
}

contract HelpersTest is Test {
    Zenith public target;

    function setUp() public {
        vm.createSelectFork("https://rpc.holesky.ethpandaops.io");
        target = new Zenith(0x29403F107781ea45Bf93710abf8df13F67f2008f);
    }

    function check_signature() public {
        bytes32 hash = 0xdcd0af9a45fa82dcdd1e4f9ef703d8cd459b6950c0638154c67117e86facf9c1;
        uint8 v = 28;
        bytes32 r = 0xb89764d107f812dbbebb925711b320d336ff8d03f08570f051123df86334f3f5;
        bytes32 s = 0x394cd592577ce6307154045607b9b18ecc1de0eb636e996981477c2d9b1a7675;
        address signer = ecrecover(hash, v, r, s);
        vm.label(signer, "recovered signer");
        assertEq(signer, 0x5b0517Dc94c413a5871536872605522E54C85a03);
    }
}
