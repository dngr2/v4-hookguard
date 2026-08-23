// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";

/// @notice Fuzz driver: runs bounded swaps and liquidity changes through the real routers against
///         the pool under test. Reverting draws are simply skipped (fail_on_revert = false).
contract PoolFuzzHandler is Test {
    PoolSwapTest internal immutable swapRouter;
    PoolModifyLiquidityTest internal immutable liqRouter;
    PoolKey internal key;
    Currency internal immutable c0;
    Currency internal immutable c1;
    uint256 internal nonce;

    constructor(PoolSwapTest _swap, PoolModifyLiquidityTest _liq, PoolKey memory _key, Currency _c0, Currency _c1) {
        swapRouter = _swap;
        liqRouter = _liq;
        key = _key;
        c0 = _c0;
        c1 = _c1;
        deal(Currency.unwrap(c0), address(this), 1e30);
        deal(Currency.unwrap(c1), address(this), 1e30);
        IERC20Minimal(Currency.unwrap(c0)).approve(address(swapRouter), type(uint256).max);
        IERC20Minimal(Currency.unwrap(c1)).approve(address(swapRouter), type(uint256).max);
        IERC20Minimal(Currency.unwrap(c0)).approve(address(liqRouter), type(uint256).max);
        IERC20Minimal(Currency.unwrap(c1)).approve(address(liqRouter), type(uint256).max);
    }

    function swap(uint256 amount, bool zeroForOne) external {
        amount = bound(amount, 1e6, 1e18);
        uint160 limit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        swapRouter.swap(
            key,
            IPoolManager.SwapParams(zeroForOne, -int256(amount), limit),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
    }

    /// @dev Each add opens a FRESH position (unique salt). Re-using a fee-bearing position would make
    ///      PoolModifyLiquidityTest collect fees and trip its own delta-sign assert — a router quirk,
    ///      not a property of the hook. Fresh positions keep the campaign exercising the hook cleanly.
    function addLiquidity(uint256 amount) external {
        amount = bound(amount, 1e15, 1e21);
        bytes32 salt = bytes32(++nonce);
        liqRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(-120, 120, int256(amount), salt), "");
    }
}

/// @title HookInvariantHarness — the property every v4 hook must keep: it retains no value it isn't owed
/// @notice A hook sits in the middle of every swap and liquidity change. A buggy or malicious hook can
///         skim value out of swappers/LPs into itself — over-charging a fee, taking a return-delta it
///         isn't entitled to, or accumulating claims. This harness stands a REAL PoolManager + pool up,
///         fuzzes swaps and liquidity through it, and asserts after every call that the hook holds no
///         value: no ERC-6909 claim on either pool currency and no direct token balance.
///
///         Extend it, implement {_setUpHook} to deploy your hook (at a permission-flagged address) and
///         return it, and Foundry fuzzes the pool and checks the property. A hook that is supposed to
///         collect a fee should hold that fee in its OWN accounting, not sit on pool currency inside
///         the manager — override {_hookIsEntitledToHold} if your design intentionally custodies value.
abstract contract HookInvariantHarness is Deployers {
    using CurrencyLibrary for Currency;

    IHooks internal hook;

    /// @dev Deploy your hook at a permission-flagged address and return it.
    function _setUpHook() internal virtual returns (IHooks);

    function setUp() public virtual {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        hook = _setUpHook();
        (key,) = initPoolAndAddLiquidity(currency0, currency1, hook, 3000, SQRT_PRICE_1_1);

        PoolFuzzHandler handler = new PoolFuzzHandler(swapRouter, modifyLiquidityRouter, key, currency0, currency1);
        targetContract(address(handler));
    }

    /// Invariant: the hook accrues no value inside the pool — neither an ERC-6909 claim on a pool
    /// currency nor a direct token balance of one.
    function invariant_hookRetainsNoValue() public view {
        address h = address(hook);
        assertEq(manager.balanceOf(h, currency0.toId()), 0, "hook accrued a currency0 claim in the PoolManager");
        assertEq(manager.balanceOf(h, currency1.toId()), 0, "hook accrued a currency1 claim in the PoolManager");
        assertEq(currency0.balanceOf(h), 0, "hook holds currency0 directly");
        assertEq(currency1.balanceOf(h), 0, "hook holds currency1 directly");
    }
}
