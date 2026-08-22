// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {OnlyPoolManagerCheck} from "../src/checks/OnlyPoolManagerCheck.sol";
import {GuardedHook, UnguardedHook} from "./reference/RefHooks.sol";

// Deploy the reference hooks to addresses whose low bits carry BEFORE_SWAP_FLAG (1<<7) and
// AFTER_SWAP_FLAG (1<<6) — i.e. low 14 bits == 0xC0 — so the check exercises those callbacks.
address constant GUARDED_ADDR = address(uint160(0xAAAA00C0));
address constant UNGUARDED_ADDR = address(uint160(0xBBBB00C0));

/// The check PASSES on a hook whose active callbacks are gated to the PoolManager.
contract OnlyPoolManagerCheckTest is OnlyPoolManagerCheck {
    address manager = makeAddr("poolManager");

    function _deploy(string memory what, address where) internal returns (address) {
        deployCodeTo(what, abi.encode(manager), where);
        return where;
    }

    function test_guardedHook_passesTheCheck() public {
        address g = _deploy("RefHooks.sol:GuardedHook", GUARDED_ADDR);
        assertCallbacksGuarded(IHooks(g), manager); // no assertion failure

        // and the predicate agrees it is fully gated
        (bool gatedAll,) = scanCallbacks(IHooks(g), manager);
        assertTrue(gatedAll, "guarded hook should scan as fully gated");
    }

    function test_check_catchesUnguardedHook() public {
        address u = _deploy("RefHooks.sol:UnguardedHook", UNGUARDED_ADDR);
        // Falsifiability: the same scan that passes the guarded hook flags the unguarded one.
        (bool gatedAll, string memory offender) = scanCallbacks(IHooks(u), manager);
        assertFalse(gatedAll, "check must flag the unguarded hook");
        assertEq(
            offender,
            "UNGUARDED CALLBACK: beforeSwap is not gated to the PoolManager",
            "first offender should be beforeSwap"
        );
    }
}

/// Concrete proof the flagged hook is actually exploitable: a stranger drives its oracle state.
contract OnlyPoolManagerDemo is Test {
    address manager = makeAddr("poolManager");
    address attacker = makeAddr("attacker");

    PoolKey key;
    IPoolManager.SwapParams swap =
        IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -1e18, sqrtPriceLimitX96: uint160(4295128740)});

    function setUp() public {
        key = PoolKey({
            currency0: Currency.wrap(address(0x1111)),
            currency1: Currency.wrap(address(0x2222)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
    }

    function test_unguarded_strangerMovesTheHookState() public {
        UnguardedHook u = new UnguardedHook(manager);
        assertEq(u.observationCount(), 0);

        // A stranger (not the PoolManager) drives beforeSwap and advances the hook's oracle state.
        vm.prank(attacker);
        u.beforeSwap(attacker, key, swap, "");
        assertEq(u.observationCount(), 1, "attacker moved the hook's state out-of-band");
    }

    function test_guarded_strangerIsRejected() public {
        GuardedHook g = new GuardedHook(manager);

        vm.prank(attacker);
        vm.expectRevert(GuardedHook.NotPoolManager.selector);
        g.beforeSwap(attacker, key, swap, "");

        // the PoolManager itself is allowed through
        vm.prank(manager);
        g.beforeSwap(manager, key, swap, "");
        assertEq(g.observationCount(), 1, "PoolManager call is accepted");
    }
}
