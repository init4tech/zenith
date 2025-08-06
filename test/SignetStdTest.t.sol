// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {RollupOrders} from "../src/orders/RollupOrders.sol";
import {RollupPassage} from "../src/passage/RollupPassage.sol";
import {Zenith} from "../src/Zenith.sol";
import {Transactor} from "../src/Transactor.sol";
import {HostOrders} from "../src/orders/HostOrders.sol";
import {Passage} from "../src/passage/Passage.sol";
// utils
import {SignetStd} from "./SignetStd.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Test} from "forge-std/Test.sol";

contract SignetStdTest is SignetStd, Test {
    function setupStd() internal virtual override {
        // if Foundry chain ID, deploy test contracts
        if (block.chainid == 31337) {
            ROLLUP_CHAIN_ID = 31337; // Localhost chain ID
            ROLLUP_PASSAGE = new RollupPassage(PERMIT2);
            ROLLUP_ORDERS = new RollupOrders(PERMIT2);
            ROLLUP_WETH = new TestERC20("Wrapped Ether", "WETH", 18);
            ROLLUP_WBTC = new TestERC20("Wrapped Bitcoin", "WBTC", 8);
            ROLLUP_WUSD = new TestERC20("Wrapped USD", "WUSD", 18); // TODO: make it a real WETH!

            HOST_CHAIN_ID = 31337; // Localhost chain ID
            HOST_USDC = new TestERC20("USD Coin", "USDC", 6);
            HOST_USDT = new TestERC20("Tether USD", "USDT", 6);
            HOST_WBTC = new TestERC20("Wrapped Bitcoin", "WBTC", 8);
            HOST_WETH = new TestERC20("Wrapped Ether", "WETH", 18); // TODO: make it a real WETH!
            TOKEN_ADMIN = address(this);
            GAS_ADMIN = address(this);
            SEQUENCER_ADMIN = address(this);
            // after setting up tokens and admin addresses, deploy system contracts
            HOST_PASSAGE = new Passage(ROLLUP_CHAIN_ID, TOKEN_ADMIN, initialEnterTokens(), PERMIT2);
            HOST_ORDERS = new HostOrders(PERMIT2);
            HOST_ZENITH = new Zenith(SEQUENCER_ADMIN);
            HOST_TRANSACTOR = new Transactor(ROLLUP_CHAIN_ID, GAS_ADMIN, HOST_PASSAGE, 30_000_000, 5_000_000);

            // TODO: Etch Permit2 code to Permit2 address
        } else {
            // otherwise, setup environment with constants
            super.setupStd();
        }
    }

    function initialEnterTokens() internal view returns (address[] memory) {
        address[] memory tokens = new address[](4);
        tokens[0] = address(HOST_USDC);
        tokens[1] = address(HOST_USDT);
        tokens[2] = address(HOST_WBTC);
        tokens[3] = address(HOST_WETH);
        return tokens;
    }
}

contract TestERC20 is ERC20Burnable {
    uint8 private _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }
}
