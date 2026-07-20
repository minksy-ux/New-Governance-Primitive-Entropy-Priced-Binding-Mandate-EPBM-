// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPersonhoodRegistry} from "./interfaces/IPersonhoodRegistry.sol";

/// @title PersonhoodRegistry
/// @notice Admin-controlled registry of proof-of-personhood / reputation scores.
///
/// Scores range from 0 (unverified / bot) to 100 (fully verified human).
///
/// Production extensions (not implemented here):
///   - Semaphore ZK membership proofs
///   - Worldcoin World ID verification
///   - Gitcoin Passport composite score
///   - On-chain social graph attestations (EAS)
///
/// The admin role is meant to be held by a multi-sig or future EPBM mandate,
/// making the registry itself governed by the protocol it helps secure.
contract PersonhoodRegistry is IPersonhoodRegistry {
    // ─── State ────────────────────────────────────────────────────────────────

    address public admin;
    address public pendingAdmin;

    /// @dev Score per account in [0, 100].  Unset accounts return 0.
    mapping(address => uint256) private _scores;

    // ─── Events ───────────────────────────────────────────────────────────────

    event ScoreSet(address indexed account, uint256 score);
    event AdminTransferInitiated(address indexed newAdmin);
    event AdminTransferAccepted(address indexed newAdmin);

    // ─── Errors ───────────────────────────────────────────────────────────────

    error Unauthorized();
    error ScoreOutOfRange(uint256 score);
    error NoPendingTransfer();

    // ─── Constructor ──────────────────────────────────────────────────────────

    constructor(address _admin) {
        admin = _admin;
    }

    // ─── Modifiers ────────────────────────────────────────────────────────────

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Unauthorized();
        _;
    }

    // ─── Admin functions ──────────────────────────────────────────────────────

    /// @notice Set the personhood score for a single account.
    /// @param account Target address
    /// @param score   Score in [0, 100]
    function setScore(address account, uint256 score) external onlyAdmin {
        if (score > 100) revert ScoreOutOfRange(score);
        _scores[account] = score;
        emit ScoreSet(account, score);
    }

    /// @notice Batch-set scores.  Saves gas for bulk onboarding.
    function setScores(
        address[] calldata accounts,
        uint256[] calldata scores
    ) external onlyAdmin {
        if (accounts.length != scores.length) revert ScoreOutOfRange(0);
        for (uint256 i = 0; i < accounts.length; i++) {
            if (scores[i] > 100) revert ScoreOutOfRange(scores[i]);
            _scores[accounts[i]] = scores[i];
            emit ScoreSet(accounts[i], scores[i]);
        }
    }

    // ─── Two-step admin transfer ───────────────────────────────────────────────

    function initiateAdminTransfer(address newAdmin) external onlyAdmin {
        pendingAdmin = newAdmin;
        emit AdminTransferInitiated(newAdmin);
    }

    function acceptAdminTransfer() external {
        if (msg.sender != pendingAdmin) revert NoPendingTransfer();
        admin = pendingAdmin;
        pendingAdmin = address(0);
        emit AdminTransferAccepted(msg.sender);
    }

    // ─── IPersonhoodRegistry ──────────────────────────────────────────────────

    /// @inheritdoc IPersonhoodRegistry
    function scoreOf(address account) external view returns (uint256) {
        return _scores[account];
    }
}
