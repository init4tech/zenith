// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";

/// @notice A contract deployed to Host chain that allows tokens to enter the rollup,
///         and enables Builders to fulfill requests to exchange tokens on the Rollup for tokens on the Host.
contract ZenithAdmin is AccessControl {
    /// @notice Role that allows a key to sign commitments to rollup blocks.
    bytes32 public constant SEQUENCER_ROLE = bytes32("SEQUENCER_ROLE");

    /// @notice Admin Role that can grant and revoke Sequencer roles.
    bytes32 public constant SEQUENCER_ADMIN_ROLE = bytes32("SEQUENCER_ADMIN_ROLE");

    /// @notice Role that can withdraw funds from Passage.
    bytes32 public constant WITHDRAWAL_ADMIN_ROLE = bytes32("WITHDRAWAL_ADMIN_ROLE");

    /// @notice Thrown when a role attempts to renounce itself.
    error RenounceDisabled();

    /// @notice Thrown when attempting to set a default admin.
    error NoDefaultAdmin();

    /// @notice Thrown when attempting to transfer a non-admin role (e.g. Sequencer can't transfer its own role).
    error OnlyAdminRolesCanTransfer();

    constructor(address withdrawalAdmin, address sequencerAdmin) {
        // there is no admin for WITHDRAWAL_ADMIN_ROLE nor SEQUENCER_ADMIN_ROLE, so nobody can grantRole or revokeRole for those roles
        // the only way to change the WITHDRAWAL_ADMIN_ROLE or SEQUENCER_ADMIN_ROLE is to call transferRole
        _grantRole(WITHDRAWAL_ADMIN_ROLE, withdrawalAdmin);
        _grantRole(SEQUENCER_ADMIN_ROLE, sequencerAdmin);
        // SEQUENCER_ADMIN_ROLE can grantRole(SEQUENCER_ROLE) and revokeRole(SEQUENCER_ROLE)
        _setRoleAdmin(SEQUENCER_ROLE, SEQUENCER_ADMIN_ROLE);
    }

    /// @notice Cannot renounce a role. Admins can revoke their administrated roles. Admins cannot renounce their own role.
    function renounceRole(bytes32, address) public pure override {
        revert RenounceDisabled();
    }

    /// @notice Transfer Admin role to a new account.
    /// @dev Only callable by the current Admin role holder.
    function transferAdminRole(bytes32 role, address newAdmin) public onlyRole(role) {
        if (!isAdminRole(role)) revert OnlyAdminRolesCanTransfer();
        if (newAdmin == address(0)) revert RenounceDisabled();
        _grantRole(role, newAdmin);
        _revokeRole(role, msg.sender);
    }

    // CANNOT set default admin role (which would be admin for WITHDRAWAL_ADMIN_ROLE and SEQUENCER_ADMIN_ROLE)
    function _grantRole(bytes32 role, address account) internal override returns (bool) {
        if (role == DEFAULT_ADMIN_ROLE) revert NoDefaultAdmin();
        return super._grantRole(role, account);
    }

    // CANNOT set admin for WITHDRAWAL_ADMIN_ROLE and SEQUENCER_ADMIN_ROLE
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal override {
        if (isAdminRole(role)) revert NoDefaultAdmin();
        super._setRoleAdmin(role, adminRole);
    }

    function isAdminRole(bytes32 role) internal pure returns (bool) {
        return role == WITHDRAWAL_ADMIN_ROLE || role == SEQUENCER_ADMIN_ROLE;
    }
}
