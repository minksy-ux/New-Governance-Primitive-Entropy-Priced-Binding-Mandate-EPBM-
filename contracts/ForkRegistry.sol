// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IForkRegistry} from "./interfaces/IForkRegistry.sol";
import {ForkBranchGovernor} from "./ForkBranchGovernor.sol";

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
        uint256 supportWeight,
        uint256 thresholdWeight
    ) external onlyEPBM returns (uint256 forkId, address branchGovernor) {
        forkId = ++forkCount;
        branchGovernor = address(new ForkBranchGovernor(epbm, forkId, branchOwner));
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