// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {GovernanceToken} from "./GovernanceToken.sol";
import {ForkBranchGovernor} from "./ForkBranchGovernor.sol";
import {IForkRegistry} from "./interfaces/IForkRegistry.sol";

/// @title ForkRegistry
/// @notice Records concrete EPBM fork branches and their resolution status.
contract ForkRegistry is IForkRegistry {
    address public immutable epbm;

    uint256 public forkCount;

    mapping(uint256 => ForkBranch) private _forks;

    error NotEPBM();
    error InvalidFork();

    constructor(address _epbm) {
        epbm = _epbm;
    }

    modifier onlyEPBM() {
        if (msg.sender != epbm) revert NotEPBM();
        _;
    }

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
    ) external onlyEPBM returns (uint256 forkId, address branchGovernor) {
        if (forkSupporters.length != forkSupportWeights.length) revert InvalidFork();

        forkId = ++forkCount;

        GovernanceToken branchToken = new GovernanceToken("EPBM Fork Token", "fEPBM", address(this));
        for (uint256 i = 0; i < forkSupporters.length; i++) {
            branchToken.mint(forkSupporters[i], forkSupportWeights[i]);
        }

        branchGovernor = address(new ForkBranchGovernor(address(branchToken), forkId, branchOwner));
        ForkBranchGovernor(payable(branchGovernor)).setEPBM(epbm);

        _forks[forkId] = ForkBranch({
            forkId: forkId,
            mandateId: mandateId,
            proposer: proposer,
            branchOwner: branchOwner,
            scope: scope,
            token: token,
            personhoodRegistry: personhoodRegistry,
            sourceGovernance: governance,
            governance: branchGovernor,
            branchGovernor: branchGovernor,
            branchToken: address(branchToken),
            branchEpbm: epbm,
            treasuryBalance: treasuryBalance,
            supportWeight: supportWeight,
            thresholdWeight: thresholdWeight,
            createdAt: block.timestamp,
            finalizedAt: 0,
            resolvedAt: 0,
            supersededBy: 0,
            lifecycleState: BranchState.ACTIVE,
            active: true
        });

        emit ForkCreated(forkId, mandateId, proposer, scope, supportWeight, thresholdWeight);
    }

    function resolveFork(uint256 forkId, bool active) external onlyEPBM {
        ForkBranch storage fork = _forks[forkId];
        if (fork.forkId == 0) revert InvalidFork();
        fork.active = active;
        fork.resolvedAt = block.timestamp;
        fork.lifecycleState = BranchState.RESOLVED;
        emit ForkResolved(forkId, active);
    }

    function finalizeFork(uint256 forkId) external onlyEPBM {
        ForkBranch storage fork = _forks[forkId];
        if (fork.forkId == 0 || fork.lifecycleState != BranchState.ACTIVE) revert InvalidFork();
        fork.lifecycleState = BranchState.FINALIZED;
        fork.finalizedAt = block.timestamp;
        emit ForkFinalized(forkId);
    }

    function supersedeFork(uint256 forkId, uint256 supersedingForkId) external onlyEPBM {
        ForkBranch storage fork = _forks[forkId];
        ForkBranch storage supersedingFork = _forks[supersedingForkId];
        if (
            fork.forkId == 0
                || supersedingFork.forkId == 0
                || fork.lifecycleState == BranchState.SUPERSEDED
                || forkId == supersedingForkId
        ) {
            revert InvalidFork();
        }
        fork.lifecycleState = BranchState.SUPERSEDED;
        fork.supersededBy = supersedingForkId;
        fork.active = false;
        emit ForkSuperseded(forkId, supersedingForkId);
    }

    function getFork(uint256 forkId) external view returns (ForkBranch memory) {
        return _forks[forkId];
    }
}