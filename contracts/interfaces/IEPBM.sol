// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IEPBM
/// @notice Interface for the Entropy-Priced Binding Mandate governance primitive.
///
/// Core lifecycle:
///   propose() → castVote() [many] → evaluate() → execute() | claimExpiredBond()
///
/// State machine:
///   NONE → VOTING → PASSED | DEFEATED | VETOED
///   PASSED → EXECUTED | EXPIRED
interface IEPBM {
    // ─── Enums ────────────────────────────────────────────────────────────────

    enum MandateState {
        NONE,     // 0 – mandate does not exist
        VOTING,   // 1 – voting period open
        PASSED,   // 2 – passed quorum + threshold; awaiting execution
        DEFEATED, // 3 – failed quorum or threshold
        VETOED,   // 4 – minority veto threshold exceeded
        EXECUTED, // 5 – actions successfully executed
        EXPIRED   // 6 – passed but not executed within the execution window
    }

    enum VoteChoice {
        YES,
        NO,
        ABSTAIN
    }

    // ─── Structs ──────────────────────────────────────────────────────────────

    struct Mandate {
        uint256 id;
        address proposer;
        bytes32 descriptionHash; // keccak256 of the full description text
        bytes32 scope;           // governance domain identifier (e.g. keccak256("treasury"))
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        uint256 bondAmount;          // ETH locked by proposer
        uint256 snapshotBlock;       // block number used for vote weight snapshots
        uint256 totalEligibleWeight; // total token supply at snapshot
        uint256 votingDeadline;      // block.timestamp after which voting is closed
        uint256 executionDeadline;   // block.timestamp after which the bond is slashable
        MandateState state;
        // Vote tallies (effective weight, after personhood boost)
        uint256 yesWeight;
        uint256 noWeight;
        uint256 abstainWeight;
        // Set after evaluate()
        uint256 voteEntropy; // normalised Shannon entropy [0, WAD]
    }

    struct VoteRecord {
        VoteChoice choice;
        uint256 weight;          // effective weight (stake × personhood multiplier)
        uint256 personhoodScore; // score at time of vote [0, 100]
    }

    // ─── Events ───────────────────────────────────────────────────────────────

    event MandateCreated(
        uint256 indexed id,
        address indexed proposer,
        bytes32 descriptionHash,
        bytes32 scope,
        uint256 bond,
        uint256 votingDeadline
    );

    event VoteCast(
        uint256 indexed mandateId,
        address indexed voter,
        VoteChoice choice,
        uint256 weight,
        uint256 personhoodScore
    );

    event MandateEvaluated(
        uint256 indexed mandateId,
        MandateState outcome,
        uint256 entropy,
        uint256 totalVoted,
        uint256 yesWeight,
        uint256 noWeight
    );

    event MandateExecuted(uint256 indexed mandateId);

    event MandateExpired(uint256 indexed mandateId, uint256 slashedBond);

    event BondSlashed(uint256 indexed mandateId, address indexed proposer, uint256 amount);

    event BondReturned(uint256 indexed mandateId, address indexed proposer, uint256 amount);

    event ScopeTargetUpdated(bytes32 indexed scope, address indexed target, bool allowed);

    event ForkIntentRegistered(
        uint256 indexed mandateId,
        address indexed voter,
        uint256 weight
    );

    event ConfigUpdated();

    // ─── Errors ───────────────────────────────────────────────────────────────

    error InsufficientBond(uint256 required, uint256 provided);
    error InvalidMandateState(MandateState current);
    error VotingClosed();
    error VotingStillOpen();
    error AlreadyVoted();
    error NoVotingPower();
    error LengthMismatch();
    error ScopeTargetNotAllowed(bytes32 scope, address target);
    error ExecutionWindowExpired();
    error ExecutionWindowOpen();
    error NotProposer();
    error NotGovernance();
    error CallFailed(uint256 index);

    // ─── Core functions ───────────────────────────────────────────────────────

    /// @notice Submit a new mandate.  Caller must send at least computeRequiredBond() ETH.
    function propose(
        bytes32 descriptionHash,
        bytes32 scope,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) external payable returns (uint256 mandateId);

    /// @notice Cast a vote on an open mandate.
    function castVote(uint256 mandateId, VoteChoice choice) external;

    /// @notice Evaluate a mandate after its voting deadline.
    ///         Transitions state to PASSED, DEFEATED, or VETOED.
    function evaluate(uint256 mandateId) external returns (MandateState outcome);

    /// @notice Execute the on-chain actions of a PASSED mandate.
    ///         Must be called before executionDeadline.
    function execute(uint256 mandateId) external payable;

    /// @notice Slash the bond of a PASSED mandate that missed its execution window.
    function claimExpiredBond(uint256 mandateId) external;

    /// @notice Register minority exit intent for a PASSED or EXECUTED mandate.
    ///         Only voters who voted NO may call this.
    function registerForkIntent(uint256 mandateId) external;

    /// @notice Pull claimable bond back after a DEFEATED or VETOED outcome.
    function claimBond() external;

    function setScopeTarget(bytes32 scope, address target, bool allowed) external;

    // ─── View functions ───────────────────────────────────────────────────────

    function getMandate(uint256 mandateId) external view returns (Mandate memory);

    function getVote(uint256 mandateId, address voter) external view returns (VoteRecord memory);

    function computeRequiredBond() external view returns (uint256);

    function historicalAverageEntropy() external view returns (uint256);
}
