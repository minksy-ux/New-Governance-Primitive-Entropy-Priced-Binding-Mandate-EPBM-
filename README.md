# EPBM - Entropy-Priced Binding Mandates

Foundational protocol for trustless global governance.

Bitcoin gave the world scarce, trustless digital money.
EPBM gives the world scarce, trustless collective decisions.

## Core Innovation

Entropy-Priced Binding Mandate (EPBM) is a first-class ledger primitive for binding group decisions such as rule changes, resource allocations, and commitments.

EPBM combines:
- Entropy-priced passage costs so high-uncertainty proposals are more expensive to force through
- Dynamic quorum and veto functions tied to measurable governance entropy
- Commitment bonds with slashing and redistribution for non-fulfillment or provable bad faith
- Scoped, time-bounded effects with automatic enforcement or reversion
- Minority protections through native exit and fork rights

## Why It Matters

EPBM targets core failures in existing governance systems:
- Plutocratic capture
- Sybil amplification
- Apathy and low-information voting
- Weak credible commitment after votes pass

By integrating mechanism design, cryptography, and information theory at the consensus layer, EPBM treats decisions as protocol-native state objects rather than application calldata.

## Key Properties

- Tamper-resistant governance history with explicit expiration and reversion semantics
- Hybrid sybil resistance using stake plus non-transferable personhood/reputation signals
- Incentive alignment via entropy pricing, participation rewards, and bond penalties
- Built-in minority safeguards through scoped mandates, veto mechanics, and forkable exits
- Formal-verification-friendly core rules and upgrade pathways

## Simpler Mental Model

EPBM can be reasoned about as four compact loops:

1. Propose: lock bond, declare bounded actions.
2. Decide: weighted vote with personhood modulation.
3. Settle: execute before deadline or slash bond.
4. Exit: if minority threshold is crossed, activate fork branch and migrate treasury/governance.

This keeps the primitive legible even as optional hardening modules (timelocks, attestations, branch lifecycle) are enabled.

## Trust Assumptions (Current)

1. Personhood oracle trust:
	- Scores come from verifier-signed attestations.
	- Registry now supports multiple active verifier keys.
	- Direct admin writes can be irreversibly disabled.
2. Governance trust:
	- Governance can tune protocol parameters and treasury behavior.
	- Two-step transfer plus optional delay reduces immediate key-risk.
3. Social fallback:
	- Fork rights are the final cryptoeconomic escape hatch when governance legitimacy fails.

## Governance Capture and Social Recovery

If governance is captured, recovery path is explicit:

1. Detect: monitor anomalous config updates, treasury drains, or verifier churn.
2. Slow: enforce governance/branch action delays to expand human response time.
3. Exit: minority stakeholders register fork intent and activate a branch.
4. Re-anchor: branch governance and treasury become the new coordination anchor.
5. Ratify: social consensus (users, infra, ecosystem) chooses canonical branch legitimacy.

## Decentralization Minimization Path

Recommended sequence to minimize trusted control over time:

1. Bootstrap:
	- Keep admin/governance multisig with strict opsec and public monitoring.
2. Distribute attestation power:
	- Add multiple verifiers and publish verifier admission/removal policy.
3. Remove manual oracle override:
	- Call `disableManualScoreWrites()` in `PersonhoodRegistry` once verifier pipeline is stable.
	- For a hard trust-minimization checkpoint, call `finalizeDecentralization()` to permanently freeze admin and verifier-set mutation.
4. Increase governance latency:
	- Set non-zero governance transfer delay and branch privileged-action delays.
5. Constrain upgrade surface:
	- Move parameter changes behind mandates and documented policy bounds.
6. Entrench social-layer accountability:
	- Pre-publish fork-runbooks, incident playbooks, and canonical recovery criteria.

## Minimal Primitive Mode

To reduce long-run protocol complexity, EPBM now supports an irreversible governance-surface freeze:

1. Ensure readiness checklist is satisfied:
	- fork registry is configured
	- no pending governance transfer exists
	- governance transfer delay is at least `MIN_GOVERNANCE_TRANSFER_DELAY_FOR_FINALIZATION`
2. Call `finalizeProtocolSurface()` on EPBM once governance policy is stable.
2. This permanently disables mutable governance-surface setters:
	- scope target mutation
	- fork registry replacement
	- treasury asset registration
	- governance transfer delay changes
	- protocol config parameter updates

This keeps the live primitive smaller and easier to reason about after bootstrap.

Use `protocolSurfaceFinalizationReadiness()` to preflight these checks in one call.

## Verifier Governance Hardening

Personhood verifier governance remains a social process, but contract constraints now reduce failure modes:

1. Multi-verifier support via `setVerifierStatus`.
2. Timelocked verifier churn once manual writes are disabled:
	- queue with `queueVerifierStatusChange(address,bool)`
	- apply after delay via `setVerifierStatus(address,bool)`
3. Verifier churn floor enforcement:
	- verifier set cannot be reduced below `MIN_VERIFIERS_FOR_FINALIZATION` after manual-write disablement.
4. One-way freeze via `finalizeDecentralization()` once readiness checks pass.

These constraints reduce single-key governance risk even though verifier admission policy remains social.

## Legitimacy Boundary

Fork legitimacy still depends on ecosystem coordination that contracts cannot fully automate.

Operationally, EPBM treats legitimacy as a layered process:

1. Onchain objective checks (vote state, fork thresholds, treasury migration).
2. Public incident reporting and branch-state transparency.
3. Offchain ecosystem convergence (clients, exchanges, infra, social consensus).

The protocol can enforce procedure; communities still determine canonical legitimacy in contested events.

## Formal Verification and Mechanism Analysis Roadmap

The current test suite is broad, but security maturity requires formal and adversarial analysis beyond unit tests.

Planned work:

1. Functional invariants:
	- treasury conservation across execute/fork/withdraw paths
	- single-claim guarantees for bonds and slashed pools
	- irreversible freeze properties for EPBM and PersonhoodRegistry
2. State-machine proofs:
	- mandate lifecycle monotonicity
	- branch lifecycle monotonicity
	- governance transfer delay correctness
3. Mechanism stress analysis:
	- cartel and capture simulations under concentrated voting power
	- verifier collusion and churn scenarios
	- fork race and legitimacy-fragmentation game analysis

Practical starting point:

1. Run Monte Carlo capture sweeps with:
	- `ROUNDS=10000 npm run simulate:capture`
2. Optional CLI flag form (note extra `--` for Hardhat script args):
	- `npm run simulate:capture -- -- --rounds 10000`
3. Compare cartel win rates as you vary:
	- `baseQuorumBps`
	- `quorumEntropyFactorBps`
	- `passageThresholdBps`
	- `passageEntropyFactorBps`
	- `vetoThresholdBps`
4. Generate frontier CSV across parameter grids:
	- `ROUNDS=3000 npm run simulate:capture:sweep`
5. Write sweep output directly to file:
	- `OUT_FILE=analysis/capture-frontier.csv ROUNDS=3000 npm run simulate:capture:sweep`
6. Override sweep grids with environment lists (comma-separated integers):
	- `BASE_QUORUM_BPS_LIST`
	- `QUORUM_ENTROPY_FACTOR_BPS_LIST`
	- `PASSAGE_THRESHOLD_BPS_LIST`
	- `PASSAGE_ENTROPY_FACTOR_BPS_LIST`
	- `VETO_THRESHOLD_BPS_LIST`

## Operational Preflight

Before calling `finalizeDecentralization()` on `PersonhoodRegistry`, run the readiness preflight script:

1. With explicit address argument:
	- `npx hardhat run scripts/check-finalization-readiness.ts --network <network> -- <registryAddress>`
2. With environment variable:
	- `REGISTRY_ADDRESS=<registryAddress> npx hardhat run scripts/check-finalization-readiness.ts --network <network>`
3. Local alias:
	- `npm run check:finalization-readiness:local -- <registryAddress>`

The script exits non-zero when checklist blockers exist (manual writes not disabled, pending admin transfer, or insufficient active verifier count).

## Maturity Stage Execution Pack

This repository now includes concrete artifacts for both maturity phases requested.

### Audit-Ready Stage

Primary stage guide:
- `docs/security/AUDIT_READY_STAGE.md`

Security evidence templates:
- `docs/security/SECURITY_REPORT_TEMPLATE.md`
- `docs/security/remediation-log.csv`
- `docs/security/FORMAL_INVARIANTS_SPEC.md`
- `docs/security/formal-evidence-matrix.json`

Operational drill runbooks:
- `docs/operations/drills/capture-event-drill.md`
- `docs/operations/drills/disputed-fork-drill.md`
- `docs/operations/drills/verifier-compromise-drill.md`
- `docs/operations/public-drill-program.md`
- `docs/operations/drills/runs/WITNESS_ATTESTATION_TEMPLATE.md`

Adversarial and invariant security tests:
- `npm run test:security`

Artifact completeness gate:
- `npm run check:maturity-artifacts`

Formal evidence traceability gate:
- `npm run check:formal-evidence`

Governance transparency exporters:
- `npm run export:verifier-history -- --registry <registryAddress> --from-block <start>`
- `npm run export:fork-legitimacy -- --epbm <epbmAddress> --mandate-id <id>`

CI traceability artifacts (on push/PR):
- drill run evidence bundle (`docs/operations/drills/runs/*.md`)
- solidity coverage bundle (`coverage/**`, `coverage.json`) or coverage attempt log (`coverage-attempt.log`) when instrumentation/compiler limits are hit

First recorded drill evidence:
- `docs/operations/drills/runs/2026-07-21-capture-event-drill-run-001.md`
- `docs/operations/drills/runs/2026-07-21-disputed-fork-drill-run-001.md`
- `docs/operations/drills/runs/2026-07-21-verifier-compromise-drill-run-001.md`

### Production-Network Stage

Primary stage guide:
- `docs/production/PRODUCTION_NETWORK_STAGE.md`

Governance and incident policy artifacts:
- `docs/governance/verifier-admission-removal-constitution.md`
- `docs/governance/fork-legitimacy-transparency-standard.md`
- `docs/governance/dispute-process.md`
- `docs/governance/incident-postmortem-template.md`
- `docs/governance/parameter-policy.md`

Stress campaign tooling:
- `ROUNDS=3000 npm run simulate:capture:sweep`
- `OUT_FILE=analysis/capture-frontier.csv ROUNDS=3000 npm run simulate:capture:sweep`

### Recommended Exit-Gate Flow

1. Run adversarial + invariant suite:
	- `npm run test:security`
2. Verify maturity artifact completeness:
	- `npm run check:maturity-artifacts`
3. Verify formal evidence traceability:
	- `npm run check:formal-evidence`
4. Execute full regression suite:
	- `npm test`
5. Fill security report + remediation log from test and review outputs.
6. Publish verifier governance history and fork-legitimacy packet exports.
7. Run and record all three operations drills with external participants and witness attestations.
8. Publish production governance policy bundle and stress-envelope outputs.

## Project Status

Research and formal specification phase.

## Suggested GitHub Repository Description

EPBM: Entropy-Priced Binding Mandates - A cryptographic governance primitive for credibly neutral, binding global coordination.

## Suggested GitHub Topics

blockchain, dao, governance, decentralized-governance, mechanism-design, cryptoeconomics, proof-of-personhood, zero-knowledge, coordination-technology, public-goods, ai-governance
