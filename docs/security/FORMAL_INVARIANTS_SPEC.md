# Formal Invariants Specification

## INV-001 Treasury Conservation
Statement:
- For EPBM, locked/claimable/slashed accounting must remain conserved across propose/evaluate/execute/claimExpiredBond/withdraw.
Evidence:
- Invariant tests and accounting assertions.

## INV-002 Single-Claim Safety
Statement:
- Bond claims and slashed-bond withdrawals must not be claimable twice.
Evidence:
- Repeated-claim negative tests.

## INV-003 Mandate State Monotonicity
Statement:
- Mandate lifecycle must progress forward-only; no backward transitions.
Evidence:
- Lifecycle transition tests and invalid-state reversion checks.

## INV-004 Branch State Monotonicity
Statement:
- Fork branch lifecycle state must not regress once finalized/superseded/resolved.
Evidence:
- Branch lifecycle tests in fork workflows.

## INV-005 Governance Transfer Correctness
Statement:
- Governance transfer must respect delay, pending uniqueness, and proper acceptor.
Evidence:
- Timelock and pending-transfer tests.

## INV-006 Replay Resistance
Statement:
- Personhood attestations are single-use and domain-bound (contract + chain + typed payload).
Evidence:
- Replay tests and wrong-domain/wrong-chain negative tests.

## INV-007 Freeze Irreversibility
Statement:
- EPBM protocol-surface freeze and personhood decentralization freeze are one-way and block mutable control paths as designed.
Evidence:
- Finalization tests and post-freeze mutation reverts.

## INV-008 Verifier Governance Safety Floor
Statement:
- After manual write disablement, active verifier set must not drop below minimum floor.
Evidence:
- Safety-floor negative tests and queued verifier-change checks.
