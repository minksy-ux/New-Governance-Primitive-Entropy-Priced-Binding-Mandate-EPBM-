// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IPersonhoodRegistry
/// @notice Interface for querying proof-of-personhood / reputation scores.
///         Scores range from 0 (unverified) to 100 (fully verified).
///         In production this would be backed by ZK proofs, Worldcoin,
///         Gitcoin Passport, or other Sybil-resistance primitives.
interface IPersonhoodRegistry {
    /// @notice Returns the personhood score for `account` in [0, 100]
    function scoreOf(address account) external view returns (uint256);
}
