// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.26;

// system contracts
import {RollupOrders} from "../src/orders/RollupOrders.sol";
import {RollupPassage} from "../src/passage/RollupPassage.sol";
// permit2
import {deployPermit2} from "./DeployPermit2.s.sol";
// gnosis safe
import {deployGnosisCore, deploySafeInstance, SafeSetup} from "./DeployGnosisSafe.s.sol";
// simple erc20
import {SimpleERC20} from "simple-erc20/SimpleERC20.sol";
// utils
import {console2} from "forge-std/Script.sol";

address constant MINTER = 0x9999999999999999999999999999999999999999;
address constant OWNER_ONE = 0x1111111111111111111111111111111111111111;
address constant OWNER_TWO = 0x2222222222222222222222222222222222222222;

address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

function deployPartOne() returns (address rollupPassage, address rollupOrders, address wbtc, address usdt) {
    // NOTE: must deploy Permit2 via https://github.com/Uniswap/permit2/blob/main/script/DeployPermit2.s.sol
    // in order to properly setup _CACHED_CHAIN_ID and _CACHED_DOMAIN_SEPARATOR

    // deploy system contracts
    rollupPassage = address(new RollupPassage{salt: "zenith.rollupPassage"}(PERMIT2));
    console2.log("rollupPassage", rollupPassage);
    rollupOrders = address(new RollupOrders{salt: "zenith.rollupOrders"}(PERMIT2));
    console2.log("rollupOrders", rollupOrders);

    // deploy simple erc20 tokens
    // make minter a recognizable addrs to aid in inspecting storage layout
    wbtc = address(new SimpleERC20{salt: "zenith.wbtc"}(MINTER, "Wrapped BTC", "WBTC"));
    usdt = address(new SimpleERC20{salt: "zenith.usdt"}(MINTER, "Tether USD", "USDT"));
    console2.log("wbtc", wbtc);
    console2.log("usdt", usdt);
}

function deployPartTwo()
    returns (address gnosisFactory, address gnosisSingleton, address gnosisFallbackHandler, address usdcAdmin)
{
    // deploy gnosis safe singleton & proxy factory
    (gnosisFactory, gnosisSingleton, gnosisFallbackHandler) = deployGnosisCore();
    console2.log("gnosisFactory", gnosisFactory);
    console2.log("gnosisSingleton", gnosisSingleton);
    console2.log("gnosisFallbackHandler", gnosisFallbackHandler);

    // deploy a gnosis safe proxy as the USDC admin
    usdcAdmin = deploySafeInstance(gnosisFactory, gnosisSingleton, getUsdcAdminSetup(gnosisFallbackHandler));
    console2.log("usdcAdmin", usdcAdmin);

    // NOTE: must deploy USDC via https://github.com/circlefin/stablecoin-evm/blob/master/scripts/deploy/deploy-fiat-token.s.sol
    // cannot import USDC deploy script because of git submodules -
    // it has a different remapping for openzeppelin contracts and can't compile in this repo
}

// setup the gnosis safe with 2 owners, threshold of 1.
// make the owners recognizable addrs to aid in inspecting storage layout
function getUsdcAdminSetup(address fallbackHandler) pure returns (SafeSetup memory usdcAdminSetup) {
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
