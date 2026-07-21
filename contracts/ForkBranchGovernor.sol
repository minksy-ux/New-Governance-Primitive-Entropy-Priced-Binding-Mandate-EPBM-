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
    uint256 public privilegedActionDelay;

    uint256 public treasuryBalance;
    mapping(bytes32 => uint256) public queuedActionEta;

    event BranchOwnershipTransferInitiated(address indexed newOwner);
    event BranchOwnershipTransferred(address indexed newOwner);
    event TreasuryWithdrawn(address indexed to, uint256 amount);
    event BranchTokenMinted(address indexed to, uint256 amount);
    event BranchTokenBurned(address indexed from, uint256 amount);
    event PrivilegedActionDelayUpdated(uint256 delaySeconds);
    event PrivilegedActionQueued(bytes32 indexed actionId, uint256 executeAfter);
    event PrivilegedActionCancelled(bytes32 indexed actionId);

    error Unauthorized();
    error NoPendingTransfer();
    error InsufficientTreasury();
    error TimelockDisabled();
    error ActionNotQueued(bytes32 actionId);
    error ActionTimelockActive(bytes32 actionId, uint256 executeAfter);

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

    function setPrivilegedActionDelay(uint256 delaySeconds) external onlyBranchOwner {
        privilegedActionDelay = delaySeconds;
        emit PrivilegedActionDelayUpdated(delaySeconds);
    }

    function queuePrivilegedAction(bytes32 actionId) external onlyBranchOwner {
        if (privilegedActionDelay == 0) revert TimelockDisabled();
        uint256 eta = block.timestamp + privilegedActionDelay;
        queuedActionEta[actionId] = eta;
        emit PrivilegedActionQueued(actionId, eta);
    }

    function cancelPrivilegedAction(bytes32 actionId) external onlyBranchOwner {
        delete queuedActionEta[actionId];
        emit PrivilegedActionCancelled(actionId);
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
        _consumeQueuedAction(actionIdRotateBranchGovernance(newGovernance));
        epbm.initiateGovernanceTransfer(newGovernance);
    }

    function setBranchGovernanceTransferDelay(uint256 delaySeconds) external onlyBranchOwner {
        epbm.setGovernanceTransferDelay(delaySeconds);
    }

    function finalizeForkBranch(uint256 targetForkId) external onlyBranchOwner {
        _consumeQueuedAction(actionIdFinalizeForkBranch(targetForkId));
        epbm.finalizeForkBranch(targetForkId);
    }

    function supersedeForkBranch(uint256 targetForkId, uint256 supersedingForkId) external onlyBranchOwner {
        _consumeQueuedAction(actionIdSupersedeForkBranch(targetForkId, supersedingForkId));
        epbm.supersedeForkBranch(targetForkId, supersedingForkId);
    }

    function resolveForkBranch(uint256 targetForkId, bool active) external onlyBranchOwner {
        _consumeQueuedAction(actionIdResolveForkBranch(targetForkId, active));
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
        _consumeQueuedAction(
            actionIdUpdateConfig(
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
            )
        );
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
        _consumeQueuedAction(actionIdWithdrawTreasury(to, amount));
        if (amount > treasuryBalance) revert InsufficientTreasury();
        treasuryBalance -= amount;
        (bool ok,) = to.call{value: amount}("");
        require(ok, "Transfer failed");
        emit TreasuryWithdrawn(to, amount);
    }

    function actionIdWithdrawTreasury(address to, uint256 amount) public pure returns (bytes32) {
        return keccak256(abi.encode("withdrawTreasury", to, amount));
    }

    function actionIdRotateBranchGovernance(address newGovernance) public pure returns (bytes32) {
        return keccak256(abi.encode("rotateBranchGovernance", newGovernance));
    }

    function actionIdFinalizeForkBranch(uint256 targetForkId) public pure returns (bytes32) {
        return keccak256(abi.encode("finalizeForkBranch", targetForkId));
    }

    function actionIdSupersedeForkBranch(uint256 targetForkId, uint256 supersedingForkId) public pure returns (bytes32) {
        return keccak256(abi.encode("supersedeForkBranch", targetForkId, supersedingForkId));
    }

    function actionIdResolveForkBranch(uint256 targetForkId, bool active) public pure returns (bytes32) {
        return keccak256(abi.encode("resolveForkBranch", targetForkId, active));
    }

    function actionIdUpdateConfig(
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
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                "updateConfig",
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
            )
        );
    }

    function _consumeQueuedAction(bytes32 actionId) internal {
        uint256 delay = privilegedActionDelay;
        if (delay == 0) return;

        uint256 eta = queuedActionEta[actionId];
        if (eta == 0) revert ActionNotQueued(actionId);
        if (block.timestamp < eta) revert ActionTimelockActive(actionId, eta);
        delete queuedActionEta[actionId];
    }
}