// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {HookAddressLint} from "./HookAddressLint.sol";
import {HookPermissionLib, IHookPermissions} from "./HookPermissionLint.sol";

/// @title HookScorecard — one call for the static hook safety checks
/// @notice Aggregates v4-hookguard's static checks — the {HookAddressLint} address-bitmap sanity and
///         the {HookPermissionLint} declaration-vs-address cross-check — into a single structured
///         report. Both are pure/view: they need no pool, no manager, no deployment beyond the hook
///         itself, so this can score any hook address (including one already deployed on-chain) with a
///         single call. The behavioral checks (caller gating, return-delta, reentrancy, value
///         conservation) require a live PoolManager and are run separately.
library HookScorecard {
    using HookAddressLint for address;

    struct Report {
        bool addressWellFormed; // HookAddressLint passed
        string addressIssue; // its violation, or ""
        bool declaresPermissions; // hook implements getHookPermissions()
        bool permissionsMatchAddress; // declaration == address bitmap (true if none declared)
        string permissionIssue; // the mismatch, or ""
        bool passed; // all static checks passed
    }

    function scan(address hook) internal view returns (Report memory r) {
        // 1. Address-bitmap lint (pure): returnDelta-without-base, dead hook.
        string memory addressViolation = hook.lint();
        r.addressWellFormed = bytes(addressViolation).length == 0;
        r.addressIssue = addressViolation;

        // 2. Declared permissions vs address bitmap, when the hook declares them.
        r.permissionsMatchAddress = true;
        try IHookPermissions(hook).getHookPermissions() returns (Hooks.Permissions memory p) {
            r.declaresPermissions = true;
            uint160 declared = HookPermissionLib.toFlags(p);
            uint160 encoded = uint160(hook) & HookPermissionLib.ALL_FLAGS_MASK;
            if (declared != encoded) {
                r.permissionsMatchAddress = false;
                r.permissionIssue = "getHookPermissions() does not match the address bitmap";
            }
        } catch {
            r.declaresPermissions = false;
        }

        r.passed = r.addressWellFormed && r.permissionsMatchAddress;
    }
}
