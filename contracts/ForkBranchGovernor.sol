// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEPBM} from "./interfaces/IEPBM.sol";
import {GovernanceToken} from "./GovernanceToken.sol";

/// @title ForkBranchGovernor
/// @notice Live control contract for a forked EPBM branch.
/// @dev This contract becomes the governance address for the forked branch and
///      can forward governance actions back into EPBM while holding migrated ETH.
contract ForkBranchGovernor {
    IEPBM public epbm;
    GovernanceToken public immutable branchToken;
    address public immutable factory;
    uint256 public immutable forkId;

    address public branchOwner;
    address public pendingBranchOwner;

    uint256 public treasuryBalance;

    event BranchOwnershipTransferInitiated(address indexed newOwner);
    event BranchOwnershipTransferred(address indexed newOwner);
    event TreasuryWithdrawn(address indexed to, uint256 amount);
    event BranchTokenMinted(address indexed to, uint256 amount);
    event BranchTokenBurned(address indexed from, uint256 amount);

    error Unauthorized();
    error NoPendingTransfer();
    error InsufficientTreasury();

    modifier onlyBranchOwner() {
        if (msg.sender != branchOwner) revert Unauthorized();
        _;
    }

    constructor(address _branchToken, uint256 _forkId, address _branchOwner) {
        branchToken = GovernanceToken(_branchToken);
        factory = msg.sender;
        forkId = _forkId;
        branchOwner = _branchOwner;
    }

    receive() external payable {
        treasuryBalance += msg.value;
    }

    modifier onlyFactory() {
        if (msg.sender != factory) revert Unauthorized();
        _;
    }

    /// @notice Wire the live branch EPBM into this governor after deployment.
    function setEPBM(address _epbm) external onlyFactory {
        epbm = IEPBM(_epbm);
    }

    /// @notice Complete the governance handoff once the branch EPBM is wired.
    function bootstrapBranchMigration() external onlyFactory {
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

    /// @notice Mint branch token supply for migration corrections or branch incentives.
    function mintBranchToken(address to, uint256 amount) external onlyBranchOwner {
        branchToken.mint(to, amount);
        emit BranchTokenMinted(to, amount);
    }

    /// @notice Burn branch token supply from an account.
    function burnBranchToken(address from, uint256 amount) external onlyBranchOwner {
        branchToken.burn(from, amount);
        emit BranchTokenBurned(from, amount);
    }

    /// @notice Transfer branch EPBM governance to a successor controller.
    function rotateBranchGovernance(address newGovernance) external onlyBranchOwner {
        epbm.initiateGovernanceTransfer(newGovernance);
    }

    function setBranchGovernanceTransferDelay(uint256 delaySeconds) external onlyBranchOwner {
        epbm.setGovernanceTransferDelay(delaySeconds);
    }

    function finalizeForkBranch(uint256 targetForkId) external onlyBranchOwner {
        epbm.finalizeForkBranch(targetForkId);
    }

    function supersedeForkBranch(uint256 targetForkId, uint256 supersedingForkId) external onlyBranchOwner {
        epbm.supersedeForkBranch(targetForkId, supersedingForkId);
    }

    function resolveForkBranch(uint256 targetForkId, bool active) external onlyBranchOwner {
        epbm.resolveForkBranch(targetForkId, active);
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