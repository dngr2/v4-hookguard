// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";

/// @notice A hook that declares its permissions (the BaseHook convention). v4 core cross-checks this
///         against the address at pool init; catching a mismatch pre-deploy in a unit test is earlier.
interface IHookPermissions {
    function getHookPermissions() external view returns (Hooks.Permissions memory);
}

/// @notice The Permissions-struct → address-bit mapping, exactly as v4-core `Hooks` encodes it.
library HookPermissionLib {
    uint160 internal constant ALL_FLAGS_MASK = uint160((1 << 14) - 1);

    function toFlags(Hooks.Permissions memory p) internal pure returns (uint160 f) {
        if (p.beforeInitialize) f |= 1 << 13;
        if (p.afterInitialize) f |= 1 << 12;
        if (p.beforeAddLiquidity) f |= 1 << 11;
        if (p.afterAddLiquidity) f |= 1 << 10;
        if (p.beforeRemoveLiquidity) f |= 1 << 9;
        if (p.afterRemoveLiquidity) f |= 1 << 8;
        if (p.beforeSwap) f |= 1 << 7;
        if (p.afterSwap) f |= 1 << 6;
        if (p.beforeDonate) f |= 1 << 5;
        if (p.afterDonate) f |= 1 << 4;
        if (p.beforeSwapReturnDelta) f |= 1 << 3;
        if (p.afterSwapReturnDelta) f |= 1 << 2;
        if (p.afterAddLiquidityReturnDelta) f |= 1 << 1;
        if (p.afterRemoveLiquidityReturnDelta) f |= 1 << 0;
    }
}

/// @title HookPermissionLint — a hook's declared permissions must match its address bitmap
/// @notice A hook that implements `getHookPermissions()` (BaseHook and most frameworks do) declares
///         which callbacks it wants; the PoolManager only calls the ones encoded in the low 14 bits of
///         the hook's address. v4 core reverts `HookAddressNotValid` at pool init when the two
///         disagree — but by then the address is mined and the deploy is spent. A mismatch means the
///         hook was deployed at an unmined/miscomputed address, and its intended callbacks won't fire
///         (or fire when the code doesn't expect them). This lint catches it in a plain unit test,
///         before mining a salt or deploying — the same early, cheap value as {HookAddressLint}.
///
///         Extend it and call {assertPermissionsMatchAddress}; hooks that don't declare permissions
///         (hand-rolled `IHooks`) are reported as such, not failed.
abstract contract HookPermissionLint is Test {
    function assertPermissionsMatchAddress(address hook) internal {
        (bool ok, string memory offender) = scanPermissions(hook);
        assertTrue(ok, offender);
    }

    /// @dev Non-asserting predicate: true iff the declared permissions equal the address bitmap (or
    ///      the hook declares none). `offender` names the mismatch on failure.
    function scanPermissions(address hook) internal view returns (bool, string memory) {
        try IHookPermissions(hook).getHookPermissions() returns (Hooks.Permissions memory p) {
            uint160 declared = HookPermissionLib.toFlags(p);
            uint160 encoded = uint160(hook) & HookPermissionLib.ALL_FLAGS_MASK;
            if (declared != encoded) {
                return (false, "getHookPermissions() does not match the address bitmap (hook deployed at a wrong/unmined address)");
            }
            return (true, "");
        } catch {
            // Hand-rolled hook with no getHookPermissions() — nothing to cross-check here.
            return (true, "");
        }
    }
}
