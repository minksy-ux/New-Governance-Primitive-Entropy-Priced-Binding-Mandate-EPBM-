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
    address public verifier;

    /// @dev Score per account in [0, 100].  Unset accounts return 0.
    mapping(address => uint256) private _scores;
    mapping(bytes32 => bool) public usedAttestations;

    // ─── Events ───────────────────────────────────────────────────────────────

    event ScoreSet(address indexed account, uint256 score);
    event ScoreAttested(address indexed account, uint256 score, uint256 nonce);
    event AdminTransferInitiated(address indexed newAdmin);
    event AdminTransferAccepted(address indexed newAdmin);
    event VerifierUpdated(address indexed verifier);

    // ─── Errors ───────────────────────────────────────────────────────────────

    error Unauthorized();
    error ScoreOutOfRange(uint256 score);
    error NoPendingTransfer();
    error InvalidAttestation();
    error AttestationExpired(uint256 expiry);

    // ─── Constructor ──────────────────────────────────────────────────────────

    constructor(address _admin) {
        admin = _admin;
        verifier = _admin;
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

    /// @notice Update verifier key used to attest personhood scores.
    function setVerifier(address newVerifier) external onlyAdmin {
        verifier = newVerifier;
        emit VerifierUpdated(newVerifier);
    }

    /// @notice Set score with an off-chain verifier attestation.
    function setScoreByAttestation(
        address account,
        uint256 score,
        uint256 expiry,
        uint256 nonce,
        bytes calldata signature
    ) external {
        if (score > 100) revert ScoreOutOfRange(score);
        if (block.timestamp > expiry) revert AttestationExpired(expiry);

        bytes32 payloadHash = keccak256(
            abi.encodePacked(address(this), block.chainid, account, score, expiry, nonce)
        );
        bytes32 digest = _toEthSignedMessageHash(payloadHash);
        if (usedAttestations[digest]) revert InvalidAttestation();

        address signer = _recoverSigner(digest, signature);
        if (signer != verifier) revert InvalidAttestation();

        usedAttestations[digest] = true;
        _scores[account] = score;
        emit ScoreSet(account, score);
        emit ScoreAttested(account, score, nonce);
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

    function _toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    function _recoverSigner(bytes32 digest, bytes calldata signature) internal pure returns (address) {
        if (signature.length != 65) revert InvalidAttestation();

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        if (v < 27) v += 27;
        if (v != 27 && v != 28) revert InvalidAttestation();

        address signer = ecrecover(digest, v, r, s);
        if (signer == address(0)) revert InvalidAttestation();
        return signer;
    }
}
