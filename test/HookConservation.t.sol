// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {HookConservationHarness} from "../src/harness/HookConservationHarness.sol";
import {BenignHook, LeakHook} from "./reference/InvariantRefHooks.sol"; // force-compile for deployCodeTo

// beforeSwap (1<<7) + afterSwap (1<<6) = 0xC0
address constant BENIGN = address(uint160(0xAAAA00C0));
// afterSwap (1<<6) + afterSwapReturnDelta (1<<2) = 0x44
address constant LEAK_ADDR = address(uint160(0xDDDD0044));

/// A benign hook diverts nothing: pool + LP value is conserved across the whole fuzz campaign.
contract BenignConservationInvariant is HookConservationHarness {
    function _setUpHook() internal override returns (IHooks) {
        deployCodeTo("InvariantRefHooks.sol:BenignHook", BENIGN);
        return IHooks(BENIGN);
    }
}

/// Why this harness exists: a hook that leaks value to a THIRD PARTY ends each call holding nothing,
/// so the "hook retains no value" invariant passes — yet the pool is drained. Conservation catches it.
contract LeakConservationDemo is Deployers {
    using CurrencyLibrary for Currency;

    address internal sink = makeAddr("sink");

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        deployCodeTo("InvariantRefHooks.sol:LeakHook", abi.encode(manager, sink), LEAK_ADDR);
        (key,) = initPoolAndAddLiquidity(currency0, currency1, IHooks(LEAK_ADDR), 3000, SQRT_PRICE_1_1);
    }

    function _system(Currency c) internal view returns (uint256) {
        return c.balanceOf(address(manager)) + c.balanceOf(address(this));
    }

    function test_leakHook_drainsPool_whileHoldingNothingItself() public {
        uint256 before = _system(currency1);

        swap(key, true, -1e18, ""); // exact-input zeroForOne; output is currency1

        // The hook itself holds nothing — "hook retains no value" would pass here.
        assertEq(currency1.balanceOf(LEAK_ADDR), 0, "leak hook holds no value itself");
        assertEq(currency0.balanceOf(LEAK_ADDR), 0, "leak hook holds no value itself");
        // But value left the pool+LP system to an external address — conservation is broken.
        assertEq(currency1.balanceOf(sink), 1e6, "leaked amount landed at the external sink");
        assertEq(_system(currency1), before - 1e6, "pool + LP system lost exactly the leaked amount");
    }
}
