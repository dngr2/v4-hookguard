// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";

/// @dev A hook that maintains internal state an attacker would want to move — e.g. a running
///      observation counter standing in for a TWAP accumulator / oracle the hook feeds. If the
///      swap callbacks are callable by anyone, a stranger can advance this state out-of-band
///      (poison the oracle, then swap against the price they just moved).
abstract contract OracleHookBase {
    address public immutable poolManager;
    uint256 public observationCount;

    constructor(address _poolManager) {
        poolManager = _poolManager;
    }

    function _observe() internal {
        observationCount++;
    }
}

/// @dev CORRECT: every swap callback is gated to the PoolManager.
contract GuardedHook is OracleHookBase {
    error NotPoolManager();

    constructor(address _pm) OracleHookBase(_pm) {}

    modifier onlyPoolManager() {
        if (msg.sender != poolManager) revert NotPoolManager();
        _;
    }

    function beforeSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, bytes calldata)
        external
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        _observe();
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        onlyPoolManager
        returns (bytes4, int128)
    {
        _observe();
        return (IHooks.afterSwap.selector, int128(0));
    }
}

/// @dev BROKEN: the swap callbacks carry real state-moving logic but NO caller gate. Anyone can
///      call `beforeSwap`/`afterSwap` directly and advance `observationCount` — the exact
///      unprotected-callback footgun. v4 core still accepts this hook (its address bitmap and
///      declared permissions agree); only the missing access control is the bug.
contract UnguardedHook is OracleHookBase {
    constructor(address _pm) OracleHookBase(_pm) {}

    function beforeSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, bytes calldata)
        external
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        _observe();
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        returns (bytes4, int128)
    {
        _observe();
        return (IHooks.afterSwap.selector, int128(0));
    }
}
