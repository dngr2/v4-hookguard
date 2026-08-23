// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ReentrancyGuardCheck, IClaimable, MaliciousReentrant} from "../src/checks/ReentrancyGuardCheck.sol";
import {ReentrantPayoutHook, GuardedPayoutHook} from "./reference/RefReentrancyHooks.sol";

contract ReentrancyGuardCheckTest is ReentrancyGuardCheck {
    uint256 constant OWED = 1 ether;
    uint256 constant MAX_REENTERS = 5;

    function test_guardedHook_passesTheCheck() public {
        GuardedPayoutHook hook = new GuardedPayoutHook();
        MaliciousReentrant attacker = new MaliciousReentrant(IClaimable(address(hook)), MAX_REENTERS);

        hook.credit{value: OWED}(address(attacker)); // owed[attacker] = 1 ether
        vm.deal(address(hook), 10 ether); // hook holds far more than owed — a drain must be possible

        assertClaimNotReentrant(attacker, OWED);
    }

    function test_check_catchesReentrantHook() public {
        ReentrantPayoutHook hook = new ReentrantPayoutHook();
        MaliciousReentrant attacker = new MaliciousReentrant(IClaimable(address(hook)), MAX_REENTERS);

        hook.credit{value: OWED}(address(attacker));
        vm.deal(address(hook), 10 ether);

        (bool safe, uint256 received) = scanClaimReentrancy(attacker, OWED);
        assertFalse(safe, "check must flag the reentrant payout");
        // owed once, but paid on the initial claim + every re-entry: 1 + MAX_REENTERS claims.
        assertEq(received, OWED * (1 + MAX_REENTERS), "attacker drained 6x its owed balance");
    }
}
