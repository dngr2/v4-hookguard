// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title HookAddressLint — pure, pre-deploy sanity of a Uniswap v4 hook address bitmap
/// @notice v4 encodes a hook's active callbacks in the low 14 bits of its address. Two classes
///         of misconfiguration are cheap to catch statically, before you mine a salt or deploy:
///
///         1. A `*ReturnDelta` flag set without its base callback flag. The pool manager would
///            expect the hook to return a delta from a callback it is never actually invoked
///            for. (v4 core rejects this at pool init; catching it in a unit test is earlier
///            and cheaper, and applies to hooks tested in isolation with no pool.)
///
///         2. A non-zero hook address with NO permission flags set — a "dead hook". The whole
///            point of a hook is that the PoolManager calls it; an address with a zero bitmap
///            is never called, so all of the hook's logic is silently dead. This is the classic
///            outcome of deploying without mining the address, and nothing on-chain flags it.
library HookAddressLint {
    uint160 internal constant ALL_FLAGS_MASK = uint160((1 << 14) - 1);

    uint160 internal constant AFTER_ADD_LIQUIDITY_FLAG = 1 << 10;
    uint160 internal constant AFTER_REMOVE_LIQUIDITY_FLAG = 1 << 8;
    uint160 internal constant BEFORE_SWAP_FLAG = 1 << 7;
    uint160 internal constant AFTER_SWAP_FLAG = 1 << 6;

    uint160 internal constant BEFORE_SWAP_RETURNS_DELTA_FLAG = 1 << 3;
    uint160 internal constant AFTER_SWAP_RETURNS_DELTA_FLAG = 1 << 2;
    uint160 internal constant AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG = 1 << 1;
    uint160 internal constant AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG = 1 << 0;

    /// @return violation an empty string if the address bitmap is well-formed, else a diagnostic.
    function lint(address hook) internal pure returns (string memory violation) {
        uint160 flags = uint160(hook) & ALL_FLAGS_MASK;

        if (flags & BEFORE_SWAP_RETURNS_DELTA_FLAG != 0 && flags & BEFORE_SWAP_FLAG == 0) {
            return "beforeSwapReturnDelta flag set without beforeSwap";
        }
        if (flags & AFTER_SWAP_RETURNS_DELTA_FLAG != 0 && flags & AFTER_SWAP_FLAG == 0) {
            return "afterSwapReturnDelta flag set without afterSwap";
        }
        if (flags & AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG != 0 && flags & AFTER_ADD_LIQUIDITY_FLAG == 0) {
            return "afterAddLiquidityReturnDelta flag set without afterAddLiquidity";
        }
        if (flags & AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG != 0 && flags & AFTER_REMOVE_LIQUIDITY_FLAG == 0) {
            return "afterRemoveLiquidityReturnDelta flag set without afterRemoveLiquidity";
        }
        if (hook != address(0) && flags == 0) {
            return "dead hook: non-zero address with no permission flags is never called by the PoolManager";
        }
        return "";
    }

    function isWellFormed(address hook) internal pure returns (bool) {
        return bytes(lint(hook)).length == 0;
    }
}
