// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEPBM} from "./interfaces/IEPBM.sol";

/// @title ForkBranchGovernor
/// @notice Live control contract for a forked EPBM branch.
/// @dev This contract becomes the governance address for the forked branch and
///      can forward governance actions back into EPBM while holding migrated ETH.
contract ForkBranchGovernor {
    IEPBM public immutable epbm;
    uint256 public immutable forkId;

    address public branchOwner;
    address public pendingBranchOwner;

    uint256 public treasuryBalance;

    event BranchOwnershipTransferInitiated(address indexed newOwner);
    event BranchOwnershipTransferred(address indexed newOwner);
    event TreasuryWithdrawn(address indexed to, uint256 amount);

    error Unauthorized();
    error NoPendingTransfer();
    error InsufficientTreasury();

    modifier onlyBranchOwner() {
        if (msg.sender != branchOwner) revert Unauthorized();
        _;
    }

    constructor(address _epbm, uint256 _forkId, address _branchOwner) {
        epbm = IEPBM(_epbm);
        forkId = _forkId;
        branchOwner = _branchOwner;
    }

    receive() external payable {
        treasuryBalance += msg.value;
    }

    /// @notice Finalizes the governance transfer after EPBM sets this contract as pending governor.
    function bootstrapForkMigration() external {
        epbm.acceptGovernanceTransfer();
    }

    function initiateBranchOwnershipTransfer(address newOwner) external onlyBranchOwner {
        pendingBranchOwner = newOwner;
        emit BranchOwnershipTransferInitiated(newOwner);
    }

    function acceptBranchOwnershipTransfer() external {
        if (msg.sender != pendingBranchOwner) revert NoPendingTransfer();
        branchOwner = pendingBranchOwner;
        pendingBranchOwner = address(0);
        emit BranchOwnershipTransferred(branchOwner);
    }

    function setScopeTarget(bytes32 scope, address target, bool allowed) external onlyBranchOwner {
        epbm.setScopeTarget(scope, target, allowed);
    }

    function updateConfig(
        uint256 _baseBond,
        uint256 _bondEntropyFactor,
        uint256 _baseQuorumBPS,
        uint256 _quorumEntropyFactor,
        uint256 _passageThresholdBPS,
        uint256 _passageEntropyFactor,
        uint256 _vetoThresholdBPS,
        uint256 _forkActivationThresholdBPS,
        uint256 _votingPeriod,
        uint256 _executionWindow,
        uint256 _personhoodBoostFactor
    ) external onlyBranchOwner {
        epbm.updateConfig(
            _baseBond,
            _bondEntropyFactor,
            _baseQuorumBPS,
            _quorumEntropyFactor,
            _passageThresholdBPS,
            _passageEntropyFactor,
            _vetoThresholdBPS,
            _forkActivationThresholdBPS,
            _votingPeriod,
            _executionWindow,
            _personhoodBoostFactor
        );
    }

    function withdrawTreasury(address payable to, uint256 amount) external onlyBranchOwner {
        if (amount > treasuryBalance) revert InsufficientTreasury();
        treasuryBalance -= amount;
        (bool ok,) = to.call{value: amount}("");
        require(ok, "Transfer failed");
        emit TreasuryWithdrawn(to, amount);
    }
}