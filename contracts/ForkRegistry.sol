// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EPBM} from "./EPBM.sol";
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

        EPBM parent = EPBM(payable(epbm));
        forkId = ++forkCount;

        GovernanceToken branchToken = new GovernanceToken("EPBM Fork Token", "fEPBM", address(this));
        for (uint256 i = 0; i < forkSupporters.length; i++) {
            branchToken.mint(forkSupporters[i], forkSupportWeights[i]);
        }

        branchGovernor = address(new ForkBranchGovernor(address(branchToken), forkId, branchOwner));

        EPBM branchEpbm = new EPBM(
            address(branchToken),
            personhoodRegistry,
            address(branchGovernor),
            parent.baseBond(),
            parent.bondEntropyFactor(),
            parent.baseQuorumBPS(),
            parent.quorumEntropyFactor(),
            parent.passageThresholdBPS(),
            parent.passageEntropyFactor(),
            parent.vetoThresholdBPS(),
            parent.forkActivationThresholdBPS(),
            parent.votingPeriod(),
            parent.executionWindow(),
            parent.personhoodBoostFactor()
        );

        branchEpbm.initiateGovernanceTransfer(branchGovernor);
        ForkBranchGovernor(payable(branchGovernor)).setEPBM(address(branchEpbm));
        ForkBranchGovernor(payable(branchGovernor)).bootstrapBranchMigration();

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
            branchEpbm: address(branchEpbm),
            treasuryBalance: treasuryBalance,
            supportWeight: supportWeight,
            thresholdWeight: thresholdWeight,
            createdAt: block.timestamp,
            active: true
        });

        emit ForkCreated(forkId, mandateId, proposer, scope, supportWeight, thresholdWeight);
    }

    function resolveFork(uint256 forkId, bool active) external onlyEPBM {
        ForkBranch storage fork = _forks[forkId];
        if (fork.forkId == 0) revert InvalidFork();
        fork.active = active;
        emit ForkResolved(forkId, active);
    }

    function getFork(uint256 forkId) external view returns (ForkBranch memory) {
        return _forks[forkId];
    }
}