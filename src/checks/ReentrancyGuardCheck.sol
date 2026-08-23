// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

/// @notice A hook that custodies value and pays it out — a fee hook, a tip/reward hook, a hook that
///         returns collected value to users. Its payout entrypoint is what this check probes.
interface IClaimable {
    function claim() external;
}

/// @notice Reusable attacker: re-enters the hook's `claim` from its payout callback (its `receive`).
///         Provided by the check so a hook author does not have to write the reentrancy harness.
contract MaliciousReentrant {
    IClaimable public immutable hook;
    uint256 public immutable maxReenters;
    uint256 public reenters;

    constructor(IClaimable _hook, uint256 _maxReenters) {
        hook = _hook;
        maxReenters = _maxReenters;
    }

    function attack() external {
        hook.claim();
    }

    receive() external payable {
        if (reenters < maxReenters) {
            reenters++;
            hook.claim();
        }
    }
}

/// @title ReentrancyGuardCheck — a hook's value payout must survive a re-entrant claimant
/// @notice The reentrancy-through-unlock footgun, and the pattern behind several real hook exploits.
///         A hook that holds value and pays it out — settling a fee to a recipient, returning a
///         tip, refunding a user — often does the payout with a raw external transfer (native value,
///         or `manager.take` inside an `unlock` callback that hands control to the recipient). If the
///         hook zeroes the recipient's owed balance AFTER that transfer (a checks-effects-interactions
///         violation) rather than before, the recipient re-enters `claim` while its balance still
///         reads as owed and withdraws again and again — draining far more than it was owed. A single
///         honest claim by an EOA passes every happy-path test; only a re-entrant contract exposes it.
///
///         The check runs a re-entrant claimant against the hook's payout and asserts it never
///         receives more than it was owed. Set the hook up so the attacker is owed `owedAmount` and
///         the hook holds more than that (a drain must be *possible* for the test to be meaningful),
///         then call {assertClaimNotReentrant}. A correct hook (effects before interaction, or a
///         reentrancy guard) lets the attacker take exactly what it is owed; a vulnerable one lets it
///         take the lot.
abstract contract ReentrancyGuardCheck is Test {
    function assertClaimNotReentrant(MaliciousReentrant attacker, uint256 owedAmount) internal {
        (bool safe, uint256 received) = scanClaimReentrancy(attacker, owedAmount);
        assertTrue(
            safe,
            "reentrant claim drained more than owed (payout is missing checks-effects-interactions / a reentrancy guard)"
        );
        received; // referenced for clarity; the boolean carries the verdict
    }

    /// @dev Non-asserting predicate: runs the attack and reports whether the attacker over-drew, and
    ///      by how much. `safe` is true iff it received no more than `owedAmount`.
    function scanClaimReentrancy(MaliciousReentrant attacker, uint256 owedAmount)
        internal
        returns (bool safe, uint256 received)
    {
        uint256 balanceBefore = address(attacker).balance;
        attacker.attack();
        received = address(attacker).balance - balanceBefore;
        safe = received <= owedAmount;
    }
}
