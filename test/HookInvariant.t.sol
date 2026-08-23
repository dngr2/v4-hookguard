// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {HookInvariantHarness} from "../src/harness/HookInvariantHarness.sol";
import {BenignHook, SkimHook} from "./reference/InvariantRefHooks.sol"; // force-compile for deployCodeTo

// beforeSwap (1<<7) + afterSwap (1<<6) = 0xC0
address constant BENIGN = address(uint160(0xAAAA00C0));
// afterSwap (1<<6) + afterSwapReturnDelta (1<<2) = 0x44
address constant SKIM = address(uint160(0xBBBB0044));

/// The harness runs a real fuzz campaign (swaps + liquidity through a live PoolManager) and the
/// invariant holds for a benign hook that takes nothing.
contract BenignHookInvariant is HookInvariantHarness {
    function _setUpHook() internal override returns (IHooks) {
        deployCodeTo("InvariantRefHooks.sol:BenignHook", BENIGN);
        return IHooks(BENIGN);
    }
}

/// Falsifiability: the same property the harness checks is violated by a skimming hook — a single
/// swap leaves it holding pool value it was never owed.
contract SkimHookDemo is Deployers {
    using CurrencyLibrary for Currency;

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        deployCodeTo("InvariantRefHooks.sol:SkimHook", abi.encode(manager), SKIM);
        (key,) = initPoolAndAddLiquidity(currency0, currency1, IHooks(SKIM), 3000, SQRT_PRICE_1_1);
    }

    function test_skimHook_accruesValue() public {
        assertEq(currency1.balanceOf(SKIM), 0, "hook starts empty");
        swap(key, true, -1e18, ""); // exact-input zeroForOne; output is currency1
        assertGt(currency1.balanceOf(SKIM), 0, "skim hook accrued pool value the harness invariant catches");
    }
}
