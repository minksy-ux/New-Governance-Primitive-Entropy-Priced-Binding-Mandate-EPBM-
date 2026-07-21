// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEPBM}                from "./interfaces/IEPBM.sol";
import {IForkRegistry}        from "./interfaces/IForkRegistry.sol";
import {ForkBranchGovernor}   from "./ForkBranchGovernor.sol";
import {IVotes}               from "./interfaces/IVotes.sol";
import {IPersonhoodRegistry}  from "./interfaces/IPersonhoodRegistry.sol";
import {EntropyLib}           from "./libraries/EntropyLib.sol";

/// @title EPBM — Entropy-Priced Binding Mandate
/// @notice First-class ledger primitive for trustless, binding group decisions.
///
/// ┌─────────────────────────────────────────────────────────────────────────┐
/// │  DESIGN OVERVIEW                                                        │
/// │                                                                         │
/// │  1. ENTROPY-PRICED BONDS                                                │
/// │     Proposers lock an ETH bond scaled by recent governance entropy.     │
/// │     When the system has historically contested votes the bond is        │
/// │     higher, raising the cost of spurious or bad-faith proposals.       │
/// │                                                                         │
/// │  2. DYNAMIC QUORUM & PASSAGE THRESHOLD                                  │
/// │     Both quorum and the YES-fraction required for passage increase      │
/// │     with the *within-vote* Shannon entropy.  A highly contested         │
/// │     proposal needs stronger consensus to pass.                          │
/// │                                                                         │
/// │  3. COMMITMENT BONDS (slash on non-fulfillment)                         │
/// │     A PASSED mandate that is not executed before executionDeadline       │
/// │     has its bond slashed.  Successful execution returns the bond.       │
/// │                                                                         │
/// │  4. MINORITY VETO & FORK RIGHTS                                         │
/// │     If NO votes exceed vetoThresholdBPS of total eligible weight the    │
/// │     mandate is VETOED.  If enough minority support registers fork       │
/// │     intent before execution, the mandate is marked FORKED and its bond  │
/// │     is returned instead of being executable.                            │
/// │                                                                         │
/// │  5. SCOPED, TIME-BOUNDED EFFECTS                                        │
/// │     Each mandate carries a scope identifier and an execution deadline.  │
/// │     Actions that are not executed automatically revert (EXPIRED state). │
/// │                                                                         │
/// │  6. SYBIL RESISTANCE                                                    │
/// │     Vote weight = stakeWeight × (1 + personhoodBoostFactor × score/100)│
/// │     where score ∈ [0,100] comes from PersonhoodRegistry.                │
/// └─────────────────────────────────────────────────────────────────────────┘
///
/// Security notes
/// --------------
/// • execute() sets state to EXECUTED before making external calls (CEI).
/// • Bond payouts use a pull pattern (claimableBonds) to prevent reentrancy.
/// • Vote weights are read from a snapshot checkpoint on the IVotes token,
///   preventing flash-loan manipulation.
/// • Only the governance address (initially the deployer, transferable via
///   mandate) can update protocol parameters.
contract EPBM is IEPBM {
    using EntropyLib for *;

    // ─────────────────────────────────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────────────────────────────────

    uint256 public constant WAD = 1e18;
    uint256 public constant BPS_DENOM = 10_000;

    /// @notice Number of past mandates used to compute historical entropy.
    uint256 public constant ENTROPY_WINDOW = 8;

    // ─────────────────────────────────────────────────────────────────────────
    // Protocol configuration (updatable by governance)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice ETH bond required when historical governance entropy is zero.
    uint256 public baseBond;

    /// @notice Multiplier that scales the bond with historical entropy.
    ///         requiredBond = baseBond × (WAD + bondEntropyFactor × avgEntropy) / WAD
    uint256 public bondEntropyFactor;

    /// @notice Minimum fraction of total eligible weight that must vote [BPS].
    uint256 public baseQuorumBPS;

    /// @notice Extra quorum per WAD of within-vote entropy [BPS].
    ///         adjustedQuorum = baseQuorumBPS + quorumEntropyFactor × entropy / WAD
    uint256 public quorumEntropyFactor;

    /// @notice YES fraction of contested votes (YES+NO) needed to pass at zero entropy [BPS].
    uint256 public passageThresholdBPS;

    /// @notice Extra passage threshold per WAD of within-vote entropy [BPS].
    uint256 public passageEntropyFactor;

    /// @notice Minority veto: if NO/totalEligible > vetoThresholdBPS the mandate is vetoed.
    uint256 public vetoThresholdBPS;

    /// @notice Length of the voting period in seconds.
    uint256 public votingPeriod;

    /// @notice How long (seconds) after passage the proposer has to execute.
    uint256 public executionWindow;

    /// @notice Minimum minority exit support required to activate a fork [BPS].
    uint256 public forkActivationThresholdBPS;

    /// @notice Personhood weight boost.
    ///         effectiveWeight = stakeWeight × (WAD + personhoodBoostFactor × score / 100) / WAD
    uint256 public personhoodBoostFactor;

    // ─────────────────────────────────────────────────────────────────────────
    // External contracts
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice ERC20Votes-compatible governance token (for snapshot vote weights).
    IVotes public token;

    /// @notice Personhood / reputation registry.
    IPersonhoodRegistry public personhoodRegistry;

    /// @notice Registry that records concrete fork branches.
    IForkRegistry public forkRegistry;

    /// @notice Address with power to update protocol config.
    ///         In production, set this to address(this) and route changes through mandates.
    address public governance;
    address public pendingGovernance;

    /// @notice Allowed execution targets per scope.
    mapping(bytes32 => mapping(address => bool)) public scopeTargetAllowed;

    // ─────────────────────────────────────────────────────────────────────────
    // Mandate storage
    // ─────────────────────────────────────────────────────────────────────────

    uint256 public mandateCount;

    mapping(uint256 => Mandate) private _mandates;
    mapping(uint256 => mapping(address => VoteRecord)) private _votes;
    mapping(uint256 => mapping(address => bool)) private _forkIntents;
    mapping(uint256 => uint256) public forkIntentWeight;
    mapping(uint256 => uint256) public forkIdByMandate;
    mapping(uint256 => address[]) private _forkSupporters;

    error ForkRegistryNotSet();

    // ─────────────────────────────────────────────────────────────────────────
    // Entropy history ring-buffer
    // ─────────────────────────────────────────────────────────────────────────

    uint256[8] private _entropyHistory; // WAD-scaled normalised entropy per mandate
    uint256 private _entropyHead;       // next write position (wraps mod ENTROPY_WINDOW)
    uint256 private _entropyCount;      // number of populated entries, capped at ENTROPY_WINDOW

    // ─────────────────────────────────────────────────────────────────────────
    // Pull-payment accounting
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Pending bond returns for proposers (pull pattern).
    mapping(address => uint256) public claimableBonds;

    /// @notice Accumulated slashed bonds held for the governance treasury.
    uint256 public slashedBondPool;

    // ─────────────────────────────────────────────────────────────────────────
    // Reentrancy guard
    // ─────────────────────────────────────────────────────────────────────────

    uint256 private _locked = 1;

    modifier nonReentrant() {
        require(_locked == 1, "Reentrant call");
        _locked = 2;
        _;
        _locked = 1;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    constructor(
        address _token,
        address _personhoodRegistry,
        address _forkRegistry,
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
    ) {
        governance            = msg.sender;
        token                 = IVotes(_token);
        personhoodRegistry    = IPersonhoodRegistry(_personhoodRegistry);
        forkRegistry          = IForkRegistry(_forkRegistry);
        baseBond              = _baseBond;
        bondEntropyFactor     = _bondEntropyFactor;
        baseQuorumBPS         = _baseQuorumBPS;
        quorumEntropyFactor   = _quorumEntropyFactor;
        passageThresholdBPS   = _passageThresholdBPS;
        passageEntropyFactor  = _passageEntropyFactor;
        vetoThresholdBPS      = _vetoThresholdBPS;
        forkActivationThresholdBPS = _forkActivationThresholdBPS;
        votingPeriod          = _votingPeriod;
        executionWindow       = _executionWindow;
        personhoodBoostFactor = _personhoodBoostFactor;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Core: propose
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IEPBM
    function propose(
        bytes32 descriptionHash,
        bytes32 scope,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) external payable nonReentrant returns (uint256 mandateId) {
        if (targets.length == 0 || targets.length != values.length || targets.length != calldatas.length) {
            revert LengthMismatch();
        }

        for (uint256 i = 0; i < targets.length; i++) {
            if (!scopeTargetAllowed[scope][targets[i]]) {
                revert ScopeTargetNotAllowed(scope, targets[i]);
            }
        }

        uint256 required = computeRequiredBond();
        if (msg.value < required) revert InsufficientBond(required, msg.value);

        mandateId = ++mandateCount;

        Mandate storage m = _mandates[mandateId];
        m.id                  = mandateId;
        m.proposer            = msg.sender;
        m.descriptionHash     = descriptionHash;
        m.scope               = scope;
        m.targets             = targets;
        m.values              = values;
        m.calldatas           = calldatas;
        m.bondAmount          = required;
        m.snapshotBlock       = block.number - 1; // use previous block for snapshot safety
        m.totalEligibleWeight = token.getPastTotalSupply(block.number - 1);
        m.votingDeadline      = block.timestamp + votingPeriod;
        m.executionDeadline   = m.votingDeadline + executionWindow;
        m.state               = MandateState.VOTING;

        emit MandateCreated(mandateId, msg.sender, descriptionHash, scope, required, m.votingDeadline);

        // Refund excess ETH to proposer
        uint256 excess = msg.value - required;
        if (excess > 0) {
            (bool ok,) = msg.sender.call{value: excess}("");
            require(ok, "Refund failed");
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Core: vote
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IEPBM
    function castVote(uint256 mandateId, VoteChoice choice) external {
        Mandate storage m = _mandates[mandateId];
        if (m.state != MandateState.VOTING)          revert InvalidMandateState(m.state);
        if (block.timestamp >= m.votingDeadline)     revert VotingClosed();
        if (_votes[mandateId][msg.sender].weight > 0) revert AlreadyVoted();

        // Read vote weight from token snapshot — prevents flash-loan manipulation
        uint256 stakeWeight = token.getPastVotes(msg.sender, m.snapshotBlock);
        if (stakeWeight == 0) revert NoVotingPower();

        // Personalhood boost: effectiveWeight = stake × (1 + boostFactor × score/100)
        uint256 score = personhoodRegistry.scoreOf(msg.sender);
        uint256 effectiveWeight = stakeWeight
            + (stakeWeight * personhoodBoostFactor * score) / (100 * WAD);

        _votes[mandateId][msg.sender] = VoteRecord({
            choice:          choice,
            weight:          effectiveWeight,
            personhoodScore: score
        });

        if (choice == VoteChoice.YES) {
            m.yesWeight += effectiveWeight;
        } else if (choice == VoteChoice.NO) {
            m.noWeight += effectiveWeight;
        } else {
            m.abstainWeight += effectiveWeight;
        }

        emit VoteCast(mandateId, msg.sender, choice, effectiveWeight, score);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Core: evaluate
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IEPBM
    /// @dev Anyone may call evaluate() once the voting deadline has passed.
    function evaluate(uint256 mandateId) external returns (MandateState outcome) {
        outcome = _evaluate(mandateId);
    }

    function _evaluate(uint256 mandateId) internal returns (MandateState outcome) {
        Mandate storage m = _mandates[mandateId];
        if (m.state != MandateState.VOTING)       revert InvalidMandateState(m.state);
        if (block.timestamp < m.votingDeadline)   revert VotingStillOpen();

        uint256 totalVoted = m.yesWeight + m.noWeight + m.abstainWeight;

        // ── Entropy ───────────────────────────────────────────────────────────
        uint256 entropy = EntropyLib.normalizedEntropy(m.yesWeight, m.noWeight, m.abstainWeight);
        m.voteEntropy = entropy;

        // Record in ring-buffer for historical averaging
        _entropyHistory[_entropyHead % ENTROPY_WINDOW] = entropy;
        _entropyHead++;
        if (_entropyCount < ENTROPY_WINDOW) {
            _entropyCount++;
        }

        // ── Veto check ────────────────────────────────────────────────────────
        // If NO weight exceeds vetoThresholdBPS of total eligible, mandate is vetoed.
        bool vetoed = m.totalEligibleWeight > 0
            && (m.noWeight * BPS_DENOM) / m.totalEligibleWeight > vetoThresholdBPS;

        // ── Quorum check ──────────────────────────────────────────────────────
        // adjustedQuorumBPS increases with entropy (more contested → higher bar)
        uint256 adjustedQuorumBPS = baseQuorumBPS + (quorumEntropyFactor * entropy) / WAD;
        if (adjustedQuorumBPS > BPS_DENOM) adjustedQuorumBPS = BPS_DENOM;
        uint256 quorumWeight = (m.totalEligibleWeight * adjustedQuorumBPS) / BPS_DENOM;
        bool quorumMet = totalVoted >= quorumWeight;

        // ── Passage check ─────────────────────────────────────────────────────
        // adjustedPassageBPS increases with entropy
        uint256 adjustedPassageBPS = passageThresholdBPS + (passageEntropyFactor * entropy) / WAD;
        if (adjustedPassageBPS > BPS_DENOM) adjustedPassageBPS = BPS_DENOM;

        uint256 contestedWeight = m.yesWeight + m.noWeight;
        bool passed = !vetoed
            && quorumMet
            && contestedWeight > 0
            && (m.yesWeight * BPS_DENOM) / contestedWeight > adjustedPassageBPS;

        // ── State transition ──────────────────────────────────────────────────
        if (vetoed) {
            m.state = MandateState.VETOED;
            _queueBondReturn(m); // veto is a legitimate outcome; return bond
        } else if (passed) {
            m.state = MandateState.PASSED;
            // Bond is held until execute() or claimExpiredBond()
        } else {
            m.state = MandateState.DEFEATED;
            _queueBondReturn(m); // legitimate defeat; return bond
        }

        outcome = m.state;
        emit MandateEvaluated(mandateId, outcome, entropy, totalVoted, m.yesWeight, m.noWeight);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Core: execute
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IEPBM
    /// @dev Caller must supply ETH equal to sum(values) for the mandate's actions.
    ///      State is set to EXECUTED *before* external calls (CEI pattern).
    function execute(uint256 mandateId) external payable nonReentrant {
        Mandate storage m = _mandates[mandateId];
        if (m.state != MandateState.PASSED)             revert InvalidMandateState(m.state);
        if (block.timestamp > m.executionDeadline)       revert ExecutionWindowExpired();

        // Verify ETH sent matches sum of action values
        uint256 totalValue;
        for (uint256 i = 0; i < m.values.length; i++) {
            totalValue += m.values[i];
        }
        require(msg.value == totalValue, "EPBM: wrong ETH for actions");

        // ── CEI: update state first ───────────────────────────────────────────
        m.state = MandateState.EXECUTED;
        uint256 bond = m.bondAmount;
        m.bondAmount = 0;

        // ── Execute each scoped action ────────────────────────────────────────
        for (uint256 i = 0; i < m.targets.length; i++) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool ok, bytes memory ret) = m.targets[i].call{value: m.values[i]}(m.calldatas[i]);
            if (!ok) {
                if (ret.length > 0) {
                    // Bubble up revert reason
                    assembly {
                        revert(add(32, ret), mload(ret))
                    }
                }
                revert CallFailed(i);
            }
        }

        // ── Return bond to proposer (pull pattern) ────────────────────────────
        claimableBonds[m.proposer] += bond;

        emit MandateExecuted(mandateId);
        emit BondReturned(mandateId, m.proposer, bond);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Core: expired bond slash
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IEPBM
    function claimExpiredBond(uint256 mandateId) external {
        Mandate storage m = _mandates[mandateId];

        if (m.state == MandateState.VOTING) {
            if (block.timestamp < m.votingDeadline) revert VotingStillOpen();
            _evaluate(mandateId);
        }

        if (m.state != MandateState.PASSED)         revert InvalidMandateState(m.state);
        if (block.timestamp <= m.executionDeadline) revert ExecutionWindowOpen();

        m.state = MandateState.EXPIRED;
        uint256 bond = m.bondAmount;
        m.bondAmount = 0;
        slashedBondPool += bond;

        emit MandateExpired(mandateId, bond);
        emit BondSlashed(mandateId, m.proposer, bond);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Minority exit
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IEPBM
    /// @dev Fork intent becomes actionable once the registered minority weight
    ///      crosses forkActivationThresholdBPS of eligible weight.
    function registerForkIntent(uint256 mandateId) external nonReentrant {
        Mandate storage m = _mandates[mandateId];
        if (m.state != MandateState.PASSED) {
            revert InvalidMandateState(m.state);
        }
        if (block.timestamp > m.executionDeadline) revert ExecutionWindowExpired();
        VoteRecord storage v = _votes[mandateId][msg.sender];
        if (v.choice != VoteChoice.NO || v.weight == 0) revert NoVotingPower();

        if (_forkIntents[mandateId][msg.sender]) revert ForkIntentAlreadyRegistered();

        _forkIntents[mandateId][msg.sender] = true;
        _forkSupporters[mandateId].push(msg.sender);
        forkIntentWeight[mandateId] += v.weight;

        emit ForkIntentRegistered(mandateId, msg.sender, v.weight);

        uint256 thresholdWeight = (m.totalEligibleWeight * forkActivationThresholdBPS) / BPS_DENOM;
        if (thresholdWeight > 0 && forkIntentWeight[mandateId] >= thresholdWeight) {
            m.state = MandateState.FORKED;
            if (address(forkRegistry) == address(0)) revert ForkRegistryNotSet();
            uint256 forkTreasury = slashedBondPool;
            slashedBondPool = 0;

            (uint256 forkId, address branchGovernor) = forkRegistry.createFork(
                mandateId,
                m.proposer,
                msg.sender,
                m.scope,
                address(token),
                address(personhoodRegistry),
                governance,
                forkTreasury,
                _forkSupporters[mandateId],
                _forkSupporterWeights(mandateId),
                forkIntentWeight[mandateId],
                thresholdWeight
            );
            forkIdByMandate[mandateId] = forkId;

            governance = branchGovernor;

            if (forkTreasury > 0) {
                (bool ok,) = payable(branchGovernor).call{value: forkTreasury}("");
                require(ok, "Fork treasury transfer failed");
            }

            _queueBondReturn(m);
            emit MandateForked(mandateId, forkIntentWeight[mandateId], thresholdWeight);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Pull-payment: bond claims
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IEPBM
    function claimBond() external nonReentrant {
        uint256 amount = claimableBonds[msg.sender];
        require(amount > 0, "Nothing to claim");
        claimableBonds[msg.sender] = 0;
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");
    }

    /// @notice Allow or disallow a target for a given scope.
    function setScopeTarget(bytes32 scope, address target, bool allowed) external onlyGovernance {
        scopeTargetAllowed[scope][target] = allowed;
        emit ScopeTargetUpdated(scope, target, allowed);
    }

    /// @notice Set or update the fork registry used to record concrete branches.
    function setForkRegistry(address _forkRegistry) external onlyGovernance {
        forkRegistry = IForkRegistry(_forkRegistry);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Governance: treasury withdrawal + config update
    // ─────────────────────────────────────────────────────────────────────────

    modifier onlyGovernance() {
        if (msg.sender != governance) revert NotGovernance();
        _;
    }

    /// @notice Two-step governance transfer — initiate phase.
    function initiateGovernanceTransfer(address newGovernance) external onlyGovernance {
        pendingGovernance = newGovernance;
    }

    /// @notice Two-step governance transfer — accept phase.
    function acceptGovernanceTransfer() external {
        require(msg.sender == pendingGovernance, "Not pending governance");
        governance = pendingGovernance;
        pendingGovernance = address(0);
    }

    /// @notice Withdraw accumulated slashed bonds to a treasury address.
    function withdrawSlashedBonds(address payable to) external onlyGovernance nonReentrant {
        uint256 amount = slashedBondPool;
        require(amount > 0, "Nothing to withdraw");
        slashedBondPool = 0;
        (bool ok,) = to.call{value: amount}("");
        require(ok, "Transfer failed");
    }

    /// @notice Update all protocol parameters in one call.
    ///         Designed to be called via a PASSED mandate (msg.sender = address(this)).
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
    ) external onlyGovernance {
        require(_baseQuorumBPS       <= BPS_DENOM, "quorum > 100%");
        require(_passageThresholdBPS <= BPS_DENOM, "passage > 100%");
        require(_vetoThresholdBPS    <= BPS_DENOM, "veto > 100%");
        require(_forkActivationThresholdBPS <= BPS_DENOM, "fork > 100%");

        baseBond              = _baseBond;
        bondEntropyFactor     = _bondEntropyFactor;
        baseQuorumBPS         = _baseQuorumBPS;
        quorumEntropyFactor   = _quorumEntropyFactor;
        passageThresholdBPS   = _passageThresholdBPS;
        passageEntropyFactor  = _passageEntropyFactor;
        vetoThresholdBPS      = _vetoThresholdBPS;
        forkActivationThresholdBPS = _forkActivationThresholdBPS;
        votingPeriod          = _votingPeriod;
        executionWindow       = _executionWindow;
        personhoodBoostFactor = _personhoodBoostFactor;

        emit ConfigUpdated();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // View functions
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IEPBM
    function getMandate(uint256 mandateId) external view returns (Mandate memory) {
        return _mandates[mandateId];
    }

    /// @inheritdoc IEPBM
    function getVote(uint256 mandateId, address voter) external view returns (VoteRecord memory) {
        return _votes[mandateId][voter];
    }

    /// @inheritdoc IEPBM
    function computeRequiredBond() public view returns (uint256) {
        uint256 avgEntropy = _historicalAverageEntropy();
        // bond = baseBond × (WAD + bondEntropyFactor × avgEntropy) / WAD
        return baseBond + (baseBond * bondEntropyFactor * avgEntropy) / (WAD * WAD);
    }

    /// @inheritdoc IEPBM
    function historicalAverageEntropy() external view returns (uint256) {
        return _historicalAverageEntropy();
    }

    /// @notice Preview mandate evaluation outcome without writing state.
    function previewEvaluation(uint256 mandateId)
        external view
        returns (
            MandateState predictedOutcome,
            uint256 entropy,
            uint256 adjustedQuorumBPS,
            uint256 adjustedPassageBPS,
            bool quorumMet,
            bool wouldVeto
        )
    {
        Mandate storage m = _mandates[mandateId];

        entropy = EntropyLib.normalizedEntropy(m.yesWeight, m.noWeight, m.abstainWeight);

        adjustedQuorumBPS = baseQuorumBPS + (quorumEntropyFactor * entropy) / WAD;
        if (adjustedQuorumBPS > BPS_DENOM) adjustedQuorumBPS = BPS_DENOM;

        adjustedPassageBPS = passageThresholdBPS + (passageEntropyFactor * entropy) / WAD;
        if (adjustedPassageBPS > BPS_DENOM) adjustedPassageBPS = BPS_DENOM;

        uint256 totalVoted = m.yesWeight + m.noWeight + m.abstainWeight;
        uint256 quorumWeight = (m.totalEligibleWeight * adjustedQuorumBPS) / BPS_DENOM;
        quorumMet = totalVoted >= quorumWeight;

        wouldVeto = m.totalEligibleWeight > 0
            && (m.noWeight * BPS_DENOM) / m.totalEligibleWeight > vetoThresholdBPS;

        uint256 contestedWeight = m.yesWeight + m.noWeight;
        bool passed = !wouldVeto
            && quorumMet
            && contestedWeight > 0
            && (m.yesWeight * BPS_DENOM) / contestedWeight > adjustedPassageBPS;

        if (wouldVeto)      predictedOutcome = MandateState.VETOED;
        else if (passed)    predictedOutcome = MandateState.PASSED;
        else                predictedOutcome = MandateState.DEFEATED;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _historicalAverageEntropy() internal view returns (uint256) {
        uint256 count = _entropyCount;
        if (count == 0) return 0;
        uint256 sum;
        for (uint256 i; i < count; i++) {
            sum += _entropyHistory[i];
        }
        return sum / count;
    }

    /// @dev Queue a bond return for the proposer (pull-payment pattern).
    function _queueBondReturn(Mandate storage m) internal {
        uint256 bond = m.bondAmount;
        if (bond == 0) return;
        m.bondAmount = 0;
        claimableBonds[m.proposer] += bond;
        emit BondReturned(m.id, m.proposer, bond);
    }

    function _forkSupporterWeights(uint256 mandateId) internal view returns (uint256[] memory weights) {
        address[] storage supporters = _forkSupporters[mandateId];
        weights = new uint256[](supporters.length);
        for (uint256 i = 0; i < supporters.length; i++) {
            weights[i] = _votes[mandateId][supporters[i]].weight;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Receive ETH (bonds + execution values)
    // ─────────────────────────────────────────────────────────────────────────

    receive() external payable {}
}
