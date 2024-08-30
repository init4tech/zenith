// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.26;

// deps
import {SafeL2} from "safe-smart-account/contracts/SafeL2.sol";
import {SafeProxyFactory} from "safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {CompatibilityFallbackHandler} from "safe-smart-account/contracts/handler/CompatibilityFallbackHandler.sol";
// script deps
import {Script, console2} from "forge-std/Script.sol";

struct SafeSetup {
    address[] owners;
    uint256 threshold;
    address to;
    bytes data;
    address fallbackHandler;
    address paymentToken;
    uint256 payment;
    address payable paymentReceiver;
    uint256 saltNonce;
}

function deployGnosisCore() returns (address factory, address singleton, address fallbackHandler) {
    factory = address(new SafeProxyFactory{salt: "zenith.gnosisFactory"}());
    singleton = address(new SafeL2{salt: "zenith.gnosisSingleton"}());
    fallbackHandler = address(new CompatibilityFallbackHandler{salt: "zenith.gnosisFallbackHandlder"}());
}

function deploySafeInstance(address factory, address singleton, SafeSetup memory setup) returns (address safe) {
    bytes memory init = abi.encodeWithSignature(
        "setup(address[],uint256,address,bytes,address,address,uint256,address)",
        setup.owners,
        setup.threshold,
        setup.to,
        setup.data,
        setup.fallbackHandler,
        setup.paymentToken,
        setup.payment,
        setup.paymentReceiver
    );
    safe = address(SafeProxyFactory(factory).createProxyWithNonce(singleton, init, setup.saltNonce));
}

contract GnosisScript is Script {
    bytes32 constant SENTINEL_VALUE = 0x0000000000000000000000000000000000000000000000000000000000000001;

    // example run:
    // forge script GnosisScript --sig "printOwnerSlots" "[0x1111111111111111111111111111111111111111, 0x2222222222222222222222222222222222222222]"
    function printOwnerSlots(address[] memory owners) public pure {
        for (uint256 i = 0; i <= owners.length; i++) {
            bytes32 value = (i == 0) ? SENTINEL_VALUE : addressToBytes32(owners[i - 1]);
            bytes32 slot = keccak256(abi.encodePacked(value, uint256(2)));
            console2.logBytes32(slot);
        }
    }

    function addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }
}
