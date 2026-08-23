// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {ReturnDeltaBoundsCheck} from "../src/checks/ReturnDeltaBoundsCheck.sol";
import {GoodReturnDeltaHook, FlatFeeHook} from "./reference/RefReturnDeltaHooks.sol";

// beforeSwap + beforeSwapReturnDelta = 0x88 (both refs are correctly flagged; only the bound differs)
address constant PCT = address(uint160(0xAAAA0088));
address constant FLAT = address(uint160(0xCCCC0088));

contract ReturnDeltaBoundsCheckTest is ReturnDeltaBoundsCheck {
    address internal pm = makeAddr("poolManager");

    function test_percentFeeHook_passesTheCheck() public {
        deployCodeTo("RefReturnDeltaHooks.sol:GoodReturnDeltaHook", abi.encode(pm), PCT);
        assertReturnDeltaBounded(IHooks(PCT), pm);
    }

    function test_check_catchesFlatFee() public {
        deployCodeTo("RefReturnDeltaHooks.sol:FlatFeeHook", abi.encode(pm), FLAT);
        (bool ok, string memory offender) = scanReturnDeltaBounds(IHooks(FLAT), pm);
        assertFalse(ok, "check must flag the flat fee that exceeds small swaps");
        assertEq(
            offender,
            "beforeSwap fee delta exceeds the swap amount for a small swap (HookDeltaExceedsSwapAmount reverts every swap that size)",
            "offender should be the bound"
        );
    }
}
