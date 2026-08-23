# v4-hookguard

Drop-in Foundry checks for the Uniswap v4 **hook** footguns that v4 core does not catch —
the class of bug where every on-chain guardrail agrees the hook is valid, yet it is exploitable
or silently inert.

Uniswap v4 moves custom logic into hooks, and with it a new attack surface. v4 core validates
one thing about a hook: that its **declared permissions match its address bitmap**
(`Hooks.validateHookPermissions`). It says nothing about whether the hook's *implementation* is
safe. `v4-hookguard` targets that gap: point a check at your hook and get a failing test — not a
vague warning — when a real hook-specific mistake is present.

Each check ships with a **correct reference hook and a deliberately broken one**, so the check is
proven to bite (no hollow assertions). Depends only on `forge-std` and `v4-core`.

## Install

```bash
forge install dngr2/v4-hookguard
```

## Checks

### 1. Unguarded callbacks  ✅ available

**The #1 hook footgun.** A callback (`beforeSwap`, `beforeAddLiquidity`, …) is *active* in the
hook's address bitmap but callable by anyone, because the implementation forgot to gate the
caller to the PoolManager. An attacker then drives the hook's logic **outside a real pool
operation**: poison an oracle/TWAP the hook maintains, move its accounting, or advance its state
right before their own swap. v4 core accepts such a hook — the address and declared permissions
agree; only the missing access control is the bug.

```solidity
import {OnlyPoolManagerCheck} from "v4-hookguard/src/checks/OnlyPoolManagerCheck.sol";

contract MyHookSecurity is OnlyPoolManagerCheck {
    function test_hookCallbacksAreGated() public {
        assertCallbacksGuarded(IHooks(address(myHook)), address(poolManager));
    }
}
```

`assertCallbacksGuarded` is **caller-differential** and needs no knowledge of your revert: it
sends each active callback once as a stranger and once as the PoolManager with identical
calldata. If the outcome is identical for both, the callback does not distinguish the PoolManager
from anyone else — it is unguarded. The reference pair proves it: the guarded hook rejects the
stranger and accepts the PoolManager; the unguarded hook lets a stranger advance its oracle state.

### 2. Hook address bitmap lint  ✅ available

Pure, pre-deploy sanity on a hook address's low 14 permission bits — catches, before you mine a
salt or deploy:
- a `*ReturnDelta` flag set without its base callback flag, and
- a **dead hook**: a non-zero address with a zero bitmap, so the PoolManager never calls it and
  all of the hook's logic is silently inert.

```solidity
import {HookAddressLint} from "v4-hookguard/src/checks/HookAddressLint.sol";
using HookAddressLint for address;
assertTrue(address(myHook).isWellFormed(), address(myHook).lint());
```

### 3. Hook invariant harness  ✅ available

A stateful fuzz campaign, not a single call. It stands up a **real `PoolManager` + your hook**,
seeds a live pool, and fuzzes swaps and liquidity through the actual v4 routers — then, after
every operation, asserts the property every hook must keep: **it retains no value it is not owed**
— no ERC-6909 claim on either pool currency inside the manager, and no direct token balance of
one. A hook that skims a return-delta, over-charges a fee into itself, or accumulates claims is
caught by a shrunk counterexample, not left for an auditor to find.

```solidity
import {HookInvariantHarness} from "v4-hookguard/src/harness/HookInvariantHarness.sol";

contract MyHookInvariant is HookInvariantHarness {
    function _setUpHook() internal override returns (IHooks) {
        // deploy your hook at its permission-flagged address and return it
        deployCodeTo("MyHook.sol:MyHook", HOOK_ADDR);
        return IHooks(HOOK_ADDR);
    }
}
```

`forge test` then fuzzes the pool against your hook and reports `invariant_hookRetainsNoValue`.
If your hook is *designed* to custody value, override `_setUpHook` accordingly or assert on its
own accounting. The reference pair proves the harness bites: a benign no-op hook holds the
invariant across thousands of operations, while a skimming hook that takes an `afterSwap`
return-delta into itself is caught leaving with pool value on a single swap.

## Roadmap (what a grant accelerates)

The three shipped checks are the foundation. The suite this grows into:

4. **Delta-conservation invariant** — extend the harness to also assert the hook never leaves an
   unsettled currency delta on the manager across a multi-hook / re-entrant `unlock` sequence.
5. **Return-delta bounds & consistency** — when a hook returns a `BeforeSwapDelta`/`int128`, it
   is within bounds and matches its declared `*ReturnDelta` permission.
6. **Reentrancy-through-unlock templates** — properties for hooks that re-enter the PoolManager's
   `unlock`, the pattern behind several hook exploits.
7. **Static hook linter + public safety scorecard** — the footgun set above extended to a
   Slither-style detector and a registry that scores deployed hooks.

## Why

v4 hooks are the newest, least-charted attack surface in DeFi, and the ecosystem is growing fast.
Shared, drop-in security tooling turns each hook-specific footgun into a red CI check for every
team shipping a hook — useful to the whole v4 ecosystem, monetizable by no one. MIT, no token,
no fees.

Built by **dngr2**, extending a public line of invariant-tested primitives and the
[invariant-kit](https://github.com/dngr2/invariant-kit) property library.
