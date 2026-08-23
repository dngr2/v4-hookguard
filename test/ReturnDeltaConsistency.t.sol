// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {ReturnDeltaConsistencyCheck} from "../src/checks/ReturnDeltaConsistencyCheck.sol";
import {GoodReturnDeltaHook, SilentDropHook} from "./reference/RefReturnDeltaHooks.sol";

// beforeSwap (1<<7 = 0x80) + beforeSwapReturnDelta (1<<3 = 0x08) = 0x88
address constant GOOD = address(uint160(0xAAAA0088));
// beforeSwap only (0x80) — returnDelta bit missing
address constant DROP = address(uint160(0xBBBB0080));

contract ReturnDeltaConsistencyCheckTest is ReturnDeltaConsistencyCheck {
    address internal pm = makeAddr("poolManager");

    function test_goodHook_passesTheCheck() public {
        deployCodeTo("RefReturnDeltaHooks.sol:GoodReturnDeltaHook", abi.encode(pm), GOOD);
        assertReturnDeltaConsistent(IHooks(GOOD), pm);

        (bool ok,) = scanReturnDelta(IHooks(GOOD), pm);
        assertTrue(ok, "flagged hook should scan clean");
    }

    function test_check_catchesSilentDrop() public {
        deployCodeTo("RefReturnDeltaHooks.sol:SilentDropHook", abi.encode(pm), DROP);
        (bool ok, string memory offender) = scanReturnDelta(IHooks(DROP), pm);
        assertFalse(ok, "check must flag the missing returnDelta bit");
        assertEq(
            offender,
            "beforeSwap returns a nonzero delta but the beforeSwapReturnDelta flag is unset (the PoolManager silently discards it)",
            "offender should be beforeSwap"
        );
    }
}

/// The two hooks return the SAME nonzero fee delta — the only difference is the deployment address
/// bit — so the bug is purely the flag mismatch, exactly what the check keys on.
contract ReturnDeltaDemo is Test {
    address internal pm = makeAddr("poolManager");

    function _callBeforeSwap(address hook) internal returns (int256) {
        IPoolManager.SwapParams memory sp =
            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: -1e18, sqrtPriceLimitX96: 0});
        PoolKey memory key;
        vm.prank(pm);
        (, BeforeSwapDelta d,) = IHooks(hook).beforeSwap(address(this), key, sp, "");
        return BeforeSwapDelta.unwrap(d);
    }

    function test_bothReturnSameDelta_onlyAddressBitDiffers() public {
        deployCodeTo("RefReturnDeltaHooks.sol:GoodReturnDeltaHook", abi.encode(pm), GOOD);
        deployCodeTo("RefReturnDeltaHooks.sol:SilentDropHook", abi.encode(pm), DROP);

        int256 good = _callBeforeSwap(GOOD);
        int256 drop = _callBeforeSwap(DROP);
        assertEq(good, drop, "identical fee behavior");
        assertTrue(good != 0, "both intend to charge a fee");
        // GOOD's address carries the returnDelta bit; DROP's does not -> DROP's fee is silently dropped.
        assertTrue(uint160(GOOD) & (1 << 3) != 0, "good has beforeSwapReturnDelta bit");
        assertTrue(uint160(DROP) & (1 << 3) == 0, "drop is missing beforeSwapReturnDelta bit");
    }
}
