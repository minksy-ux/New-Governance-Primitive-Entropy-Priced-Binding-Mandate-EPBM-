// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IForkRegistry
/// @notice Interface for tracking concrete minority exit branches created by EPBM.
interface IForkRegistry {
    enum BranchState {
        ACTIVE,
        FINALIZED,
        SUPERSEDED,
        RESOLVED
    }

    struct ForkBranch {
        uint256 forkId;
        uint256 mandateId;
        address proposer;
        address branchOwner;
        bytes32 scope;
        address token;
        address personhoodRegistry;
        address sourceGovernance;
        address governance;
        address branchGovernor;
        address branchToken;
        address branchEpbm;
        uint256 treasuryBalance;
        uint256 supportWeight;
        uint256 thresholdWeight;
        uint256 createdAt;
        uint256 finalizedAt;
        uint256 resolvedAt;
        uint256 supersededBy;
        BranchState lifecycleState;
        bool active;
    }

    event ForkCreated(
        uint256 indexed forkId,
        uint256 indexed mandateId,
        address indexed proposer,
        bytes32 scope,
        uint256 supportWeight,
        uint256 thresholdWeight
    );

    event ForkResolved(uint256 indexed forkId, bool active);
    event ForkFinalized(uint256 indexed forkId);
    event ForkSuperseded(uint256 indexed forkId, uint256 indexed supersedingForkId);

    function createFork(
        uint256 mandateId,
        address proposer,
        address branchOwner,
        bytes32 scope,
        address token,
        address personhoodRegistry,
        address governance,
        uint256 treasuryBalance,
        address[] calldata forkSupporters,
        uint256[] calldata forkSupportWeights,
        uint256 supportWeight,
        uint256 thresholdWeight
    ) external returns (uint256 forkId, address branchGovernor);

    function resolveFork(uint256 forkId, bool active) external;

    function finalizeFork(uint256 forkId) external;

    function supersedeFork(uint256 forkId, uint256 supersedingForkId) external;

    function getFork(uint256 forkId) external view returns (ForkBranch memory);
}