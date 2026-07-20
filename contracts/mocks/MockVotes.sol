// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVotes} from "../interfaces/IVotes.sol";

/// @title MockVotes
/// @notice Lightweight IVotes mock for testing.
///         All timepoints return the current balance (no real checkpointing).
contract MockVotes is IVotes {
    mapping(address => uint256) private _balances;
    uint256 private _totalSupply;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply  += amount;
    }

    function burn(address from, uint256 amount) external {
        require(_balances[from] >= amount, "Insufficient balance");
        _balances[from] -= amount;
        _totalSupply    -= amount;
    }

    /// @dev Returns current balance regardless of blockNumber.
    function getPastVotes(address account, uint256 /*blockNumber*/) external view returns (uint256) {
        return _balances[account];
    }

    /// @dev Returns current total supply regardless of blockNumber.
    function getPastTotalSupply(uint256 /*blockNumber*/) external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }
}
