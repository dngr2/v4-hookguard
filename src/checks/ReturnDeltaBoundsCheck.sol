// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";

/// @title ReturnDeltaBoundsCheck — a beforeSwap fee delta must never exceed the swap amount
/// @notice A hook that charges a fee via a `beforeSwap` specified-delta must keep that delta within
///         the swap's specified amount. v4 core enforces this hard: in `Hooks.beforeSwap`, the hook's
///         specified-delta is added to the amount to swap and, for an exact-input swap, the manager
///         reverts `HookDeltaExceedsSwapAmount` if the result crosses zero — i.e. if the fee is
///         larger than the input. So a hook that charges a FLAT fee (or any fee that can exceed a
///         small swap) does not just overcharge — it makes every swap at or below that size REVERT.
///         A denial of service for small swappers, invisible to a happy-path test that only ever
///         swaps a large, round amount.
///
///         The check samples a range of exact-input swap sizes down to dust, calls `beforeSwap` in
///         isolation as the PoolManager, and asserts the returned specified-delta stays strictly
///         within each amount. Pass the hook's PoolManager so the `onlyPoolManager` gate is met.
///         Callbacks that revert when called in isolation (they read live pool state) are skipped.
abstract contract ReturnDeltaBoundsCheck is Test {
    uint160 internal constant BEFORE_SWAP_FLAG = 1 << 7;

    function assertReturnDeltaBounded(IHooks hook, address poolManager) internal {
        (bool ok, string memory offender) = scanReturnDeltaBounds(hook, poolManager);
        assertTrue(ok, offender);
    }

    /// @dev Non-asserting predicate: true iff the beforeSwap specified-delta is within the swap
    ///      amount across the sampled sizes. `offender` names the smallest failing swap on failure.
    function scanReturnDeltaBounds(IHooks hook, address poolManager) internal returns (bool, string memory) {
        if (uint160(address(hook)) & BEFORE_SWAP_FLAG == 0) return (true, "");

        int256[6] memory amounts = [int256(1e3), 1e6, 1e9, 1e12, 1e15, 1e18];
        PoolKey memory key;

        for (uint256 i = 0; i < amounts.length; i++) {
            int256 amountSpecified = -amounts[i]; // exact input is negative
            IPoolManager.SwapParams memory sp =
                IPoolManager.SwapParams({zeroForOne: true, amountSpecified: amountSpecified, sqrtPriceLimitX96: 0});

            vm.prank(poolManager);
            (bool okc, bytes memory ret) =
                address(hook).call(abi.encodeCall(IHooks.beforeSwap, (address(this), key, sp, "")));
            if (!okc || ret.length < 96) continue;

            (, int256 packed,) = abi.decode(ret, (bytes4, int256, uint24));
            int128 deltaSpecified = int128(packed >> 128); // BeforeSwapDelta packs specified in the high 128 bits

            // exact input: the manager reverts if amountSpecified + deltaSpecified > 0,
            // i.e. if a positive fee delta exceeds the input magnitude.
            if (deltaSpecified > 0 && int256(deltaSpecified) > -amountSpecified) {
                return (
                    false,
                    "beforeSwap fee delta exceeds the swap amount for a small swap (HookDeltaExceedsSwapAmount reverts every swap that size)"
                );
            }
        }
        return (true, "");
    }
}
