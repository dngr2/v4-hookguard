// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @dev Shared: a hook that credits value to recipients and pays it out on `claim`. Models any hook
///      that custodies value (fees, tips, refunds) and later releases it. `credit` stands in for the
///      hook's real accrual path (a fee taken in a swap callback); the security question is purely
///      whether `claim` releases exactly what is owed under re-entry.
abstract contract PayoutHookBase {
    mapping(address => uint256) public owed;

    function credit(address to) external payable {
        owed[to] += msg.value;
    }

    receive() external payable {}
}

/// @dev BROKEN: zeroes the owed balance AFTER paying out. A re-entrant recipient sees a still-nonzero
///      balance and drains the hook. (Same shape whether the payout is native value or a
///      `manager.take` inside an `unlock` callback that reaches the recipient.)
contract ReentrantPayoutHook is PayoutHookBase {
    function claim() external {
        uint256 amount = owed[msg.sender];
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "payout failed");
        owed[msg.sender] = 0; // BUG: effect after interaction
    }
}

/// @dev CORRECT: zeroes the owed balance BEFORE paying out. A re-entrant recipient sees a zero
///      balance on re-entry and takes nothing more than it was owed.
contract GuardedPayoutHook is PayoutHookBase {
    function claim() external {
        uint256 amount = owed[msg.sender];
        owed[msg.sender] = 0; // effect before interaction
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "payout failed");
    }
}
