// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MockTarget
/// @notice Trivial contract for testing mandate execution.
contract MockTarget {
    uint256 public value;
    bool public called;

    event Called(address caller, uint256 amount);

    function setValue(uint256 newValue) external {
        value = newValue;
        called = true;
        emit Called(msg.sender, newValue);
    }

    function revertAlways() external pure {
        revert("MockTarget: always reverts");
    }

    receive() external payable {}
}
