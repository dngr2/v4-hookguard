// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {PoolFuzzHandler} from "./HookInvariantHarness.sol";

/// @title HookConservationHarness — a hook must not leak pool value to anyone
/// @notice A stronger sibling of the {HookInvariantHarness} "hook retains no value" invariant. That
///         one checks the HOOK holds nothing after each operation — but a hook can skim value and
///         forward it straight to a third party (a fee recipient, an attacker's address), ending each
///         call holding nothing while the pool is still drained. That invariant passes; the value is
///         gone all the same.
///
///         This harness closes the gap by conservation: with the pool and a single fuzzing LP/swapper
///         as a closed system, the total of each currency held by the PoolManager plus that actor is
///         fixed — swaps and liquidity changes only move value between them. Any value that leaves to
///         a third party makes the sum drop. It catches self-skimming AND third-party leaks.
///
///         Extend it, implement {_setUpHook}, and Foundry fuzzes swaps/liquidity and checks the sum.
abstract contract HookConservationHarness is Deployers {
    using CurrencyLibrary for Currency;

    IHooks internal hook;
    PoolFuzzHandler internal handler;
    uint256 internal initial0;
    uint256 internal initial1;

    function _setUpHook() internal virtual returns (IHooks);

    function setUp() public virtual {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        hook = _setUpHook();
        (key,) = initPoolAndAddLiquidity(currency0, currency1, hook, 3000, SQRT_PRICE_1_1);

        handler = new PoolFuzzHandler(swapRouter, modifyLiquidityRouter, key, currency0, currency1);
        targetContract(address(handler));

        initial0 = _systemHoldings(currency0);
        initial1 = _systemHoldings(currency1);
    }

    /// @dev All of a currency that lives inside the closed pool+actor system: the manager's reserves
    ///      plus the fuzzing actor's balance. Routers settle to zero within each unlock, so they hold
    ///      nothing between calls and need not be counted.
    function _systemHoldings(Currency c) internal view returns (uint256) {
        return c.balanceOf(address(manager)) + c.balanceOf(address(handler));
    }

    /// Invariant: value only moves between the pool and its LP/swapper — never out to a third party.
    function invariant_poolValueConserved() public view {
        assertEq(_systemHoldings(currency0), initial0, "currency0 leaked out of the pool + LP system");
        assertEq(_systemHoldings(currency1), initial1, "currency1 leaked out of the pool + LP system");
    }
}
