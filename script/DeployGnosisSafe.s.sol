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

address constant OWNER_ONE = 0x1111111111111111111111111111111111111111;
address constant OWNER_TWO = 0x2222222222222222222222222222222222222222;
bytes32 constant SENTINEL_VALUE = 0x0000000000000000000000000000000000000000000000000000000000000001;

contract GnosisScript is Script {
    // deploy:
    // forge script GnosisScript --sig "deployGnosis()" --rpc-url $RPC_URL --broadcast [signing args]
    function deployGnosis()
        public
        returns (address gnosisFactory, address gnosisSingleton, address gnosisFallbackHandler, address usdcAdmin)
    {
        vm.startBroadcast();

        // deploy gnosis safe singleton & proxy factory
        (gnosisFactory, gnosisSingleton, gnosisFallbackHandler) = deployGnosisCore();

        // deploy a gnosis safe proxy as the USDC admin
        usdcAdmin = deploySafeInstance(gnosisFactory, gnosisSingleton, getUsdcAdminSetup(gnosisFallbackHandler));
    }

    function deployGnosisCore() public returns (address factory, address singleton, address fallbackHandler) {
        factory = address(new SafeProxyFactory{salt: "zenith.gnosisFactory"}());
        singleton = address(new SafeL2{salt: "zenith.gnosisSingleton"}());
        fallbackHandler = address(new CompatibilityFallbackHandler{salt: "zenith.gnosisFallbackHandlder"}());
    }

    function deploySafeInstance(address factory, address singleton, SafeSetup memory setup)
        public
        returns (address safe)
    {
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

    // setup the gnosis safe with 2 owners, threshold of 1.
    // make the owners recognizable addrs to aid in inspecting storage layout
    function getUsdcAdminSetup(address fallbackHandler) public pure returns (SafeSetup memory usdcAdminSetup) {
        address[] memory owners = new address[](2);
        owners[0] = OWNER_ONE;
        owners[1] = OWNER_TWO;
        usdcAdminSetup = SafeSetup({
            owners: owners,
            threshold: 1,
            to: address(0),
            data: "",
            fallbackHandler: fallbackHandler,
            paymentToken: address(0),
            payment: 0,
            paymentReceiver: payable(address(0)),
            saltNonce: 17001
        });
    }

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
