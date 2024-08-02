// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.24;

import {OrderDestination} from "./OrderDestination.sol";
import {OrderOrigin} from "./OrderOrigin.sol";
import {UsesPermit2} from "../UsesPermit2.sol";

contract HostOrders is OrderDestination {
    constructor(address _permit2) UsesPermit2(_permit2) {}
}

contract RollupOrders is OrderOrigin, OrderDestination {
    constructor(address _permit2) UsesPermit2(_permit2) {}
}
