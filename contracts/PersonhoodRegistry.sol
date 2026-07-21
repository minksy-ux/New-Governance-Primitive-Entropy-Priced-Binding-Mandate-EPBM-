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
    bytes32 public constant ATTESTATION_TYPEHASH =
        keccak256("PersonhoodScoreAttestation(address account,uint256 score,uint256 expiry,uint256 nonce)");
    bytes32 public constant ATTESTATION_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant ATTESTATION_DOMAIN_NAME_HASH = keccak256("EPBM Personhood Registry");
    bytes32 private constant ATTESTATION_DOMAIN_VERSION_HASH = keccak256("1");
    uint256 public constant MIN_VERIFIERS_FOR_FINALIZATION = 2;
    uint256 public constant MIN_VERIFIER_CHANGE_DELAY = 1 days;

    // ─── State ────────────────────────────────────────────────────────────────

    address public admin;
    address public pendingAdmin;
    address public verifier;
    bool public manualScoreWritesDisabled;
    bool public decentralizationFinalized;
    uint256 public activeVerifierCount;
    uint256 public verifierChangeDelay;

    /// @dev Score per account in [0, 100].  Unset accounts return 0.
    mapping(address => uint256) private _scores;
    mapping(bytes32 => bool) public usedAttestations;
    mapping(address => bool) public isVerifier;
    mapping(bytes32 => uint256) public queuedVerifierChangeEta;

    // ─── Events ───────────────────────────────────────────────────────────────

    event ScoreSet(address indexed account, uint256 score);
    event ScoreAttested(address indexed account, uint256 score, uint256 nonce);
    event AdminTransferInitiated(address indexed newAdmin);
    event AdminTransferAccepted(address indexed newAdmin);
    event VerifierUpdated(address indexed verifier);
    event VerifierStatusUpdated(address indexed verifier, bool enabled);
    event VerifierChangeQueued(address indexed verifier, bool enabled, uint256 executeAfter);
    event ManualScoreWritesDisabled();
    event DecentralizationFinalized(address indexed finalAdmin);

    // ─── Errors ───────────────────────────────────────────────────────────────

    error Unauthorized();
    error ScoreOutOfRange(uint256 score);
    error NoPendingTransfer();
    error InvalidAttestation();
    error AttestationExpired(uint256 expiry);
    error ManualScoreWritesDisabledError();
    error RegistryFrozen();
    error FinalizationManualWritesNotDisabled();
    error FinalizationPendingAdminExists(address pendingAdmin);
    error FinalizationInsufficientVerifiers(uint256 activeVerifiers);
    error VerifierSafetyFloorBreached(uint256 activeVerifiers, uint256 minimumRequired);
    error VerifierChangeNotQueued(bytes32 changeId);
    error VerifierChangeTimelockActive(bytes32 changeId, uint256 executeAfter);

    // ─── Constructor ──────────────────────────────────────────────────────────

    constructor(address _admin) {
        admin = _admin;
        verifier = _admin;
        isVerifier[_admin] = true;
        activeVerifierCount = 1;
        verifierChangeDelay = MIN_VERIFIER_CHANGE_DELAY;
    }

    // ─── Modifiers ────────────────────────────────────────────────────────────

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Unauthorized();
        _;
    }

    modifier onlyAdminMutable() {
        if (msg.sender != admin) revert Unauthorized();
        if (decentralizationFinalized) revert RegistryFrozen();
        _;
    }

    // ─── Admin functions ──────────────────────────────────────────────────────

    /// @notice Set the personhood score for a single account.
    /// @param account Target address
    /// @param score   Score in [0, 100]
    function setScore(address account, uint256 score) external onlyAdminMutable {
        if (manualScoreWritesDisabled) revert ManualScoreWritesDisabledError();
        if (score > 100) revert ScoreOutOfRange(score);
        _scores[account] = score;
        emit ScoreSet(account, score);
    }

    /// @notice Batch-set scores.  Saves gas for bulk onboarding.
    function setScores(
        address[] calldata accounts,
        uint256[] calldata scores
    ) external onlyAdminMutable {
        if (manualScoreWritesDisabled) revert ManualScoreWritesDisabledError();
        if (accounts.length != scores.length) revert ScoreOutOfRange(0);
        for (uint256 i = 0; i < accounts.length; i++) {
            if (scores[i] > 100) revert ScoreOutOfRange(scores[i]);
            _scores[accounts[i]] = scores[i];
            emit ScoreSet(accounts[i], scores[i]);
        }
    }

    /// @notice Update verifier key used to attest personhood scores.
    function setVerifier(address newVerifier) external onlyAdminMutable {
        if (manualScoreWritesDisabled) revert RegistryFrozen();
        if (isVerifier[verifier]) {
            isVerifier[verifier] = false;
            activeVerifierCount -= 1;
        }
        verifier = newVerifier;
        if (!isVerifier[newVerifier]) {
            isVerifier[newVerifier] = true;
            activeVerifierCount += 1;
        }
        emit VerifierUpdated(newVerifier);
        emit VerifierStatusUpdated(newVerifier, true);
    }

    function setVerifierChangeDelay(uint256 delaySeconds) external onlyAdminMutable {
        require(delaySeconds >= MIN_VERIFIER_CHANGE_DELAY, "verifier delay too short");
        verifierChangeDelay = delaySeconds;
    }

    function queueVerifierStatusChange(address verifierAddress, bool enabled) external onlyAdminMutable {
        bytes32 changeId = _verifierChangeId(verifierAddress, enabled);
        uint256 eta = block.timestamp + verifierChangeDelay;
        queuedVerifierChangeEta[changeId] = eta;
        emit VerifierChangeQueued(verifierAddress, enabled, eta);
    }

    /// @notice Enable or disable an attestation verifier key.
    function setVerifierStatus(address verifierAddress, bool enabled) external onlyAdminMutable {
        if (manualScoreWritesDisabled) {
            bytes32 changeId = _verifierChangeId(verifierAddress, enabled);
            uint256 eta = queuedVerifierChangeEta[changeId];
            if (eta == 0) revert VerifierChangeNotQueued(changeId);
            if (block.timestamp < eta) revert VerifierChangeTimelockActive(changeId, eta);
            delete queuedVerifierChangeEta[changeId];
        }

        bool current = isVerifier[verifierAddress];
        if (current == enabled) {
            emit VerifierStatusUpdated(verifierAddress, enabled);
            return;
        }

        if (!enabled && manualScoreWritesDisabled && activeVerifierCount <= MIN_VERIFIERS_FOR_FINALIZATION) {
            revert VerifierSafetyFloorBreached(activeVerifierCount, MIN_VERIFIERS_FOR_FINALIZATION);
        }

        isVerifier[verifierAddress] = enabled;
        if (enabled) {
            activeVerifierCount += 1;
        } else {
            activeVerifierCount -= 1;
        }
        emit VerifierStatusUpdated(verifierAddress, enabled);
    }

    /// @notice Irreversibly disable direct admin score writes.
    function disableManualScoreWrites() external onlyAdminMutable {
        manualScoreWritesDisabled = true;
        emit ManualScoreWritesDisabled();
    }

    /// @notice Irreversibly freeze admin mutability and verifier-set governance.
    ///         Attestation-based score updates continue for already-enabled verifiers.
    function finalizeDecentralization() external onlyAdminMutable {
        if (!manualScoreWritesDisabled) revert FinalizationManualWritesNotDisabled();
        if (pendingAdmin != address(0)) revert FinalizationPendingAdminExists(pendingAdmin);
        if (activeVerifierCount < MIN_VERIFIERS_FOR_FINALIZATION) {
            revert FinalizationInsufficientVerifiers(activeVerifierCount);
        }
        decentralizationFinalized = true;
        emit DecentralizationFinalized(msg.sender);
    }

    /// @notice One-call preflight status for decentralization finalization.
    function finalizationReadiness()
        external
        view
        returns (
            bool ready,
            bool manualWritesDisabled,
            bool hasNoPendingAdmin,
            uint256 verifierCount,
            bool enoughVerifiers
        )
    {
        manualWritesDisabled = manualScoreWritesDisabled;
        hasNoPendingAdmin = pendingAdmin == address(0);
        verifierCount = activeVerifierCount;
        enoughVerifiers = verifierCount >= MIN_VERIFIERS_FOR_FINALIZATION;
        ready = manualWritesDisabled && hasNoPendingAdmin && enoughVerifiers;
    }

    function verifierStatusChangeReadiness(address verifierAddress, bool enabled)
        external
        view
        returns (bool ready, uint256 executeAfter)
    {
        bytes32 changeId = _verifierChangeId(verifierAddress, enabled);
        executeAfter = queuedVerifierChangeEta[changeId];
        ready = executeAfter != 0 && block.timestamp >= executeAfter;
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

        bytes32 digest = computeAttestationDigest(account, score, expiry, nonce);
        if (usedAttestations[digest]) revert InvalidAttestation();

        address signer = _recoverSigner(digest, signature);
        if (!isVerifier[signer]) revert InvalidAttestation();

        usedAttestations[digest] = true;
        _scores[account] = score;
        emit ScoreSet(account, score);
        emit ScoreAttested(account, score, nonce);
    }

    // ─── Two-step admin transfer ───────────────────────────────────────────────

    function initiateAdminTransfer(address newAdmin) external onlyAdminMutable {
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

    function computeAttestationDigest(
        address account,
        uint256 score,
        uint256 expiry,
        uint256 nonce
    ) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(ATTESTATION_TYPEHASH, account, score, expiry, nonce)
        );

        bytes32 domainSeparator = keccak256(
            abi.encode(
                ATTESTATION_DOMAIN_TYPEHASH,
                ATTESTATION_DOMAIN_NAME_HASH,
                ATTESTATION_DOMAIN_VERSION_HASH,
                block.chainid,
                address(this)
            )
        );

        bytes32 payloadHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        return _toEthSignedMessageHash(payloadHash);
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

    function _verifierChangeId(address verifierAddress, bool enabled) internal pure returns (bytes32) {
        return keccak256(abi.encode("verifier-status", verifierAddress, enabled));
    }
}
