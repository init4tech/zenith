    // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";

struct Permit {
    address token;
    address owner;
    address spender;
    uint256 value;
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
}

abstract contract PermitLib {
    function _permit(Permit memory permit) internal {
        IERC20Permit(permit.token).permit(
            permit.owner, permit.spender, permit.value, permit.deadline, permit.v, permit.r, permit.s
        );
    }

    function _permit(Permit[] memory permits) internal {
        for (uint256 i; i < permits.length; i++) {
            _permit(permits[i]);
        }
    }
}
