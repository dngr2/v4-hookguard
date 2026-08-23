// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";

/// @title ReturnDeltaConsistencyCheck — a hook's return-delta must match its address permission
/// @notice A subtle, silent Uniswap v4 hook footgun. When a hook returns a nonzero delta from
///         `beforeSwap` (a `BeforeSwapDelta`) or `afterSwap` (an `int128`) — the mechanism a hook
///         uses to charge a fee or take a share of a swap — the PoolManager only reads and applies
///         that delta if the hook's ADDRESS carries the matching `*ReturnDelta` permission bit. If
///         the hook computes and returns a delta but was deployed at an address WITHOUT that bit,
///         the manager silently discards the return value: the hook collects nothing, yet its own
///         accounting (if it recorded the fee) now disagrees with what actually settled. Every
///         happy-path test where "the swap succeeds" still passes — the loss is invisible.
///
///         This is the inverse of the {HookAddressLint} case (flag set without the base callback,
///         which v4 core rejects at init). Here the flag is MISSING while the code returns a delta,
///         which nothing on-chain rejects.
///
///         The check calls the hook's swap callbacks in isolation, as the PoolManager, with a
///         representative exact-input swap, and asserts: if a callback returns a nonzero delta, the
///         address carries the corresponding `*ReturnDelta` bit. Pass the hook's PoolManager so the
///         callback's `onlyPoolManager` gate is satisfied. Callbacks that revert when called in
///         isolation (e.g. they read live pool state) are skipped — check those with the harness.
abstract contract ReturnDeltaConsistencyCheck is Test {
    uint160 internal constant BEFORE_SWAP_FLAG = 1 << 7;
    uint160 internal constant AFTER_SWAP_FLAG = 1 << 6;
    uint160 internal constant BEFORE_SWAP_RETURNS_DELTA_FLAG = 1 << 3;
    uint160 internal constant AFTER_SWAP_RETURNS_DELTA_FLAG = 1 << 2;

    function assertReturnDeltaConsistent(IHooks hook, address poolManager) internal {
        (bool ok, string memory offender) = scanReturnDelta(hook, poolManager);
        assertTrue(ok, offender);
    }

    /// @dev Non-asserting predicate: true iff every nonzero swap return-delta is backed by the
    ///      matching `*ReturnDelta` address bit. `offender` names the callback on failure.
    function scanReturnDelta(IHooks hook, address poolManager) internal returns (bool, string memory) {
        uint160 flags = uint160(address(hook));
        PoolKey memory key;
        IPoolManager.SwapParams memory sp =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -1e18, sqrtPriceLimitX96: 0});

        if (flags & BEFORE_SWAP_FLAG != 0) {
            vm.prank(poolManager);
            (bool okc, bytes memory ret) =
                address(hook).call(abi.encodeCall(IHooks.beforeSwap, (address(this), key, sp, "")));
            if (okc && ret.length >= 96) {
                (, int256 delta,) = abi.decode(ret, (bytes4, int256, uint24));
                if (delta != 0 && flags & BEFORE_SWAP_RETURNS_DELTA_FLAG == 0) {
                    return (
                        false,
                        "beforeSwap returns a nonzero delta but the beforeSwapReturnDelta flag is unset (the PoolManager silently discards it)"
                    );
                }
            }
        }

        if (flags & AFTER_SWAP_FLAG != 0) {
            vm.prank(poolManager);
            (bool okc, bytes memory ret) = address(hook).call(
                abi.encodeCall(IHooks.afterSwap, (address(this), key, sp, BalanceDelta.wrap(0), ""))
            );
            if (okc && ret.length >= 64) {
                (, int256 delta) = abi.decode(ret, (bytes4, int256));
                if (delta != 0 && flags & AFTER_SWAP_RETURNS_DELTA_FLAG == 0) {
                    return (
                        false,
                        "afterSwap returns a nonzero delta but the afterSwapReturnDelta flag is unset (the PoolManager silently discards it)"
                    );
                }
            }
        }

        return (true, "");
    }
}
