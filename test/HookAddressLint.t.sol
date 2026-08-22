// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {HookAddressLint} from "../src/checks/HookAddressLint.sol";

contract HookAddressLintTest is Test {
    using HookAddressLint for address;

    function test_wellFormed_beforeSwapOnly() public pure {
        // low bits 0xC0 = beforeSwap + afterSwap, no return-delta flags
        assertTrue(address(uint160(0xAAAA00C0)).isWellFormed());
    }

    function test_wellFormed_beforeSwapWithReturnDelta() public pure {
        // beforeSwap (1<<7=0x80) + beforeSwapReturnDelta (1<<3=0x08) = 0x88 — dependency satisfied
        assertTrue(address(uint160(0xAAAA0088)).isWellFormed());
    }

    function test_wellFormed_hooklessPool() public pure {
        // address(0) with no flags is a valid hookless pool
        assertTrue(address(0).isWellFormed());
    }

    function test_catches_returnDeltaWithoutBase() public pure {
        // beforeSwapReturnDelta (0x08) set but beforeSwap (0x80) NOT set
        assertFalse(address(uint160(0xAAAA0008)).isWellFormed());
        assertEq(
            address(uint160(0xAAAA0008)).lint(),
            "beforeSwapReturnDelta flag set without beforeSwap"
        );
    }

    function test_catches_deadHook() public pure {
        // non-zero address, zero flags -> never called by the PoolManager
        assertFalse(address(uint160(0xAAAA0000)).isWellFormed());
        assertEq(
            address(uint160(0xAAAA0000)).lint(),
            "dead hook: non-zero address with no permission flags is never called by the PoolManager"
        );
    }

    function test_catches_afterAddLiquidityReturnDeltaWithoutBase() public pure {
        // afterAddLiquidityReturnDelta (1<<1=0x02) without afterAddLiquidity (1<<10=0x400)
        assertFalse(address(uint160(0xAAAA0002)).isWellFormed());
    }
}
