// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";

/// @dev Shared: a hook that takes a 1% fee on the swap's specified amount via a beforeSwap delta.
///      Gated to its PoolManager. The fee logic is pure — no pool state read — so it can be checked
///      in isolation. The GOOD and BROKEN variants are byte-for-byte identical in behavior; the ONLY
///      difference is the address they are meant to be deployed at (whether the returnDelta bit is set).
abstract contract FeeHookBase {
    address internal immutable poolManager;

    error NotPoolManager();

    constructor(address _poolManager) {
        poolManager = _poolManager;
    }

    modifier onlyPoolManager() {
        if (msg.sender != poolManager) revert NotPoolManager();
        _;
    }

    function _fee(IPoolManager.SwapParams calldata p) internal pure returns (int128) {
        int256 amt = p.amountSpecified < 0 ? -p.amountSpecified : p.amountSpecified;
        return int128(amt / 100); // 1% of the specified amount
    }

    function beforeSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata p, bytes calldata)
        external
        view
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        return (IHooks.beforeSwap.selector, toBeforeSwapDelta(_fee(p), 0), 0);
    }
}

/// @dev CORRECT: returns a nonzero beforeSwap delta AND is deployed at an address WITH the
///      beforeSwapReturnDelta bit (low bits 0x88 = beforeSwap 0x80 + beforeSwapReturnDelta 0x08),
///      so the PoolManager applies the fee.
contract GoodReturnDeltaHook is FeeHookBase {
    constructor(address _poolManager) FeeHookBase(_poolManager) {}
}

/// @dev BROKEN: identical fee code, but deployed at an address WITHOUT the returnDelta bit
///      (low bits 0x80 = beforeSwap only). The PoolManager silently discards the returned fee — the
///      hook collects nothing while believing it charged 1%.
contract SilentDropHook is FeeHookBase {
    constructor(address _poolManager) FeeHookBase(_poolManager) {}
}

/// @dev BROKEN (bounds): charges a FLAT fee regardless of swap size. Deployed correctly (with the
///      returnDelta bit), so it passes the consistency check — but for any exact-input swap at or
///      below FLAT_FEE the specified-delta exceeds the input and the PoolManager reverts
///      HookDeltaExceedsSwapAmount: every small swap is bricked.
contract FlatFeeHook {
    address internal immutable poolManager;
    int128 internal constant FLAT_FEE = 1e15;

    error NotPoolManager();

    constructor(address _poolManager) {
        poolManager = _poolManager;
    }

    function beforeSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, bytes calldata)
        external
        view
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (msg.sender != poolManager) revert NotPoolManager();
        return (IHooks.beforeSwap.selector, toBeforeSwapDelta(FLAT_FEE, 0), 0);
    }
}
