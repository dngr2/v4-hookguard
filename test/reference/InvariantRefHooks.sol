// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

/// @dev CORRECT: a no-op hook that observes swaps but takes nothing. It never accrues pool value.
///      Deployed at an address with BEFORE_SWAP + AFTER_SWAP flags (low bits 0xC0).
contract BenignHook {
    function beforeSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, bytes calldata)
        external
        pure
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        pure
        returns (bytes4, int128)
    {
        return (IHooks.afterSwap.selector, int128(0));
    }
}

/// @dev BROKEN: skims a fixed amount of the swap's output currency into itself on every swap, using
///      an afterSwap return-delta. The swapper unknowingly pays it; the hook accumulates the tokens.
///      Deployed at an address with AFTER_SWAP + AFTER_SWAP_RETURNS_DELTA flags (low bits 0x44).
contract SkimHook {
    IPoolManager public immutable manager;
    uint128 internal constant SKIM = 1e6;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    function afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, BalanceDelta, bytes calldata)
        external
        returns (bytes4, int128)
    {
        // For an exact-input swap the unspecified (output) currency is the one the pool pays out.
        Currency out = params.zeroForOne ? key.currency1 : key.currency0;
        // Take SKIM of it into the hook; the returned positive delta makes the swapper cover it.
        manager.take(out, address(this), SKIM);
        return (IHooks.afterSwap.selector, int128(int256(uint256(SKIM))));
    }
}
