// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {HookPermissionLint} from "../src/checks/HookPermissionLint.sol";
import {HookScorecard} from "../src/checks/HookScorecard.sol";
import {MatchingPermsHook, MismatchedPermsHook} from "./reference/RefPermissionHooks.sol";

// declared 0xC0 (beforeSwap+afterSwap), deployed at 0xC0 — match
address constant MATCH = address(uint160(0xAAAA00C0));
// declared 0x8C0 (adds beforeAddLiquidity), deployed at 0xC0 — mismatch
address constant MISMATCH = address(uint160(0xBBBB00C0));
// beforeSwapReturnDelta (0x08) without beforeSwap — a malformed address bitmap
address constant BAD_ADDR = address(uint160(0xCCCC0008));

contract HookPermissionLintTest is HookPermissionLint {
    function test_matchingHook_passesTheCheck() public {
        deployCodeTo("RefPermissionHooks.sol:MatchingPermsHook", MATCH);
        assertPermissionsMatchAddress(MATCH);
    }

    function test_check_catchesMismatch() public {
        deployCodeTo("RefPermissionHooks.sol:MismatchedPermsHook", MISMATCH);
        (bool ok, string memory offender) = scanPermissions(MISMATCH);
        assertFalse(ok, "check must flag the declaration/address mismatch");
        assertEq(
            offender,
            "getHookPermissions() does not match the address bitmap (hook deployed at a wrong/unmined address)",
            "offender should be the mismatch"
        );
    }

    function test_handRolledHook_notFailed() public {
        // BenignHook implements no getHookPermissions() — nothing to cross-check, so it passes.
        deployCodeTo("InvariantRefHooks.sol:BenignHook", MATCH);
        (bool ok,) = scanPermissions(MATCH);
        assertTrue(ok, "a hook that declares no permissions is not failed by this lint");
    }
}

contract HookScorecardTest is Test {
    function test_goodHook_scoresClean() public {
        deployCodeTo("RefPermissionHooks.sol:MatchingPermsHook", MATCH);
        HookScorecard.Report memory r = HookScorecard.scan(MATCH);
        assertTrue(r.passed, "clean hook passes the scorecard");
        assertTrue(r.addressWellFormed, "address well formed");
        assertTrue(r.declaresPermissions, "declares permissions");
        assertTrue(r.permissionsMatchAddress, "permissions match address");
    }

    function test_scorecard_flagsBadAddressBitmap() public {
        deployCodeTo("InvariantRefHooks.sol:BenignHook", BAD_ADDR);
        HookScorecard.Report memory r = HookScorecard.scan(BAD_ADDR);
        assertFalse(r.passed, "malformed address fails the scorecard");
        assertFalse(r.addressWellFormed, "address flagged");
        assertEq(r.addressIssue, "beforeSwapReturnDelta flag set without beforeSwap", "address issue reported");
    }

    function test_scorecard_flagsPermissionMismatch() public {
        deployCodeTo("RefPermissionHooks.sol:MismatchedPermsHook", MISMATCH);
        HookScorecard.Report memory r = HookScorecard.scan(MISMATCH);
        assertFalse(r.passed, "permission mismatch fails the scorecard");
        assertTrue(r.addressWellFormed, "address itself is well formed");
        assertFalse(r.permissionsMatchAddress, "permission mismatch flagged");
    }
}
