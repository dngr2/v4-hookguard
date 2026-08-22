// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";

/// @title OnlyPoolManagerCheck — every active hook callback must be gated to the PoolManager
/// @notice The #1 Uniswap v4 hook footgun that v4 core does NOT catch: a hook whose
///         callback (`beforeSwap`, `beforeAddLiquidity`, ...) is *active* in its address
///         bitmap but is callable by anyone. v4 core's `validateHookPermissions` only checks
///         that the hook's DECLARED permissions match its ADDRESS bits — it never checks that
///         the implementation restricts the caller. An unguarded active callback lets an
///         attacker drive the hook's logic OUTSIDE a real pool operation: poison an oracle the
///         hook maintains, mint/burn its accounting, front-run their own swap by moving the
///         hook's state first, or grief other users.
///
///         The check is caller-differential and needs no knowledge of the hook's specific
///         revert: it invokes each active callback once as a stranger and once as the
///         PoolManager with identical calldata. If the outcome is IDENTICAL for both callers,
///         the callback does not distinguish the PoolManager from anyone else — i.e. it is
///         unguarded. A correctly gated callback reverts (or behaves differently) for the
///         stranger, so the outcomes differ.
///
///         Extend it in a test and call {assertCallbacksGuarded} against your deployed hook.
abstract contract OnlyPoolManagerCheck is Test {
    // v4 hook-permission address bits (mirrors v4-core `Hooks`, which are internal constants).
    uint160 internal constant BEFORE_INITIALIZE_FLAG = 1 << 13;
    uint160 internal constant BEFORE_ADD_LIQUIDITY_FLAG = 1 << 11;
    uint160 internal constant BEFORE_REMOVE_LIQUIDITY_FLAG = 1 << 9;
    uint160 internal constant BEFORE_SWAP_FLAG = 1 << 7;
    uint160 internal constant AFTER_SWAP_FLAG = 1 << 6;

    function _has(IHooks hook, uint160 flag) private pure returns (bool) {
        return uint160(address(hook)) & flag != 0;
    }

    /// @dev Asserts that every state-touching callback the hook's address marks active is
    ///      gated to `manager`. `manager` must differ from this test contract (the "stranger").
    function assertCallbacksGuarded(IHooks hook, address manager) internal {
        (bool gatedAll, string memory offender) = scanCallbacks(hook, manager);
        assertTrue(gatedAll, offender);
    }

    /// @dev Non-asserting predicate: returns whether every active state-touching callback is
    ///      gated to `manager`, and the first offender's message if not. Lets a test prove the
    ///      check discriminates a guarded hook (true) from an unguarded one (false).
    function scanCallbacks(IHooks hook, address manager) internal returns (bool gatedAll, string memory offender) {
        require(manager != address(this) && manager != address(0), "SETUP: manager must be a distinct non-zero address");

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1111)),
            currency1: Currency.wrap(address(0x2222)),
            fee: 3000,
            tickSpacing: 60,
            hooks: hook
        });
        IPoolManager.SwapParams memory swap =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -1e18, sqrtPriceLimitX96: uint160(4295128740)});
        IPoolManager.ModifyLiquidityParams memory liq =
            IPoolManager.ModifyLiquidityParams({tickLower: -60, tickUpper: 60, liquidityDelta: 1e18, salt: bytes32(0)});
        address self = address(this);

        if (_has(hook, BEFORE_INITIALIZE_FLAG)
            && !_gated(hook, manager, abi.encodeCall(IHooks.beforeInitialize, (self, key, uint160(1 << 96))))) {
            return (false, "UNGUARDED CALLBACK: beforeInitialize is not gated to the PoolManager");
        }
        if (_has(hook, BEFORE_ADD_LIQUIDITY_FLAG)
            && !_gated(hook, manager, abi.encodeCall(IHooks.beforeAddLiquidity, (self, key, liq, "")))) {
            return (false, "UNGUARDED CALLBACK: beforeAddLiquidity is not gated to the PoolManager");
        }
        if (_has(hook, BEFORE_REMOVE_LIQUIDITY_FLAG)) {
            liq.liquidityDelta = -1e18;
            if (!_gated(hook, manager, abi.encodeCall(IHooks.beforeRemoveLiquidity, (self, key, liq, "")))) {
                return (false, "UNGUARDED CALLBACK: beforeRemoveLiquidity is not gated to the PoolManager");
            }
        }
        if (_has(hook, BEFORE_SWAP_FLAG)
            && !_gated(hook, manager, abi.encodeCall(IHooks.beforeSwap, (self, key, swap, "")))) {
            return (false, "UNGUARDED CALLBACK: beforeSwap is not gated to the PoolManager");
        }
        if (_has(hook, AFTER_SWAP_FLAG)
            && !_gated(hook, manager, abi.encodeCall(IHooks.afterSwap, (self, key, swap, BalanceDelta.wrap(0), "")))) {
            return (false, "UNGUARDED CALLBACK: afterSwap is not gated to the PoolManager");
        }
        return (true, "");
    }

    /// @dev A callback is gated iff its outcome depends on the caller: identical calldata sent
    ///      by a stranger vs the PoolManager must differ (revert-vs-not, or different returndata).
    ///      calldata is precomputed BEFORE the prank so the cheatcode is not consumed by an
    ///      argument expression (a known Foundry footgun).
    function _gated(IHooks hook, address manager, bytes memory data) private returns (bool) {
        (bool okStranger, bytes memory retStranger) = address(hook).call(data); // caller = this test (a stranger)

        vm.prank(manager);
        (bool okManager, bytes memory retManager) = address(hook).call(data); // caller = the PoolManager

        return (okStranger != okManager) || keccak256(retStranger) != keccak256(retManager);
    }
}
