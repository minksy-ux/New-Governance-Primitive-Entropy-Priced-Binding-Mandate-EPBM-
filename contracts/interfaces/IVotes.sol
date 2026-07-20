// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IVotes
/// @notice Minimal interface for ERC20Votes-compatible governance tokens
interface IVotes {
    /// @notice Returns the vote weight of `account` at a past block number
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256);

    /// @notice Returns the total token supply at a past block number
    function getPastTotalSupply(uint256 blockNumber) external view returns (uint256);
}
