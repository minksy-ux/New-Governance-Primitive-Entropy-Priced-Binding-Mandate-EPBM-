# Audit-Ready Stage

## Goal
Move from strong engineering to third-party security confidence.

## Scope
- EPBM core lifecycle and treasury accounting
- Fork lifecycle and branch-governor controls
- Personhood verifier governance, replay resistance, and freeze paths

## Required Deliverables

1. External security review
- At least one independent audit, ideally two independent reviews.
- All critical/high findings resolved or explicitly risk-accepted with governance sign-off.

2. Security report package
- Final report: [SECURITY_REPORT_TEMPLATE.md](SECURITY_REPORT_TEMPLATE.md)
- Remediation log: [remediation-log.csv](remediation-log.csv)
- Reproduction commands and commit SHAs for each fix.

3. Property and adversarial testing
- Differential checks: preview vs evaluate outcomes under diverse vote distributions.
- Adversarial checks: fork timing edge cases, governance freeze paths, verifier churn controls.
- CI gate: no regression in security-labeled tests.

4. Formal invariant specification
- Canonical invariant set in [FORMAL_INVARIANTS_SPEC.md](FORMAL_INVARIANTS_SPEC.md).
- Mapping from each invariant to test coverage and evidence artifact.
- Machine-checkable matrix in [formal-evidence-matrix.json](formal-evidence-matrix.json).
- Gate command: `npm run check:formal-evidence`.

5. Verifier governance transparency
- Export governance event history for personhood verifier changes.
- Command: `npm run export:verifier-history -- --registry <registryAddress> --from-block <start>`

6. Operational drill evidence
- Capture drill: [capture-event-drill.md](../operations/drills/capture-event-drill.md)
- Disputed fork drill: [disputed-fork-drill.md](../operations/drills/disputed-fork-drill.md)
- Verifier compromise drill: [verifier-compromise-drill.md](../operations/drills/verifier-compromise-drill.md)
- First recorded runs:
	- [2026-07-21-capture-event-drill-run-001.md](../operations/drills/runs/2026-07-21-capture-event-drill-run-001.md)
	- [2026-07-21-disputed-fork-drill-run-001.md](../operations/drills/runs/2026-07-21-disputed-fork-drill-run-001.md)
	- [2026-07-21-verifier-compromise-drill-run-001.md](../operations/drills/runs/2026-07-21-verifier-compromise-drill-run-001.md)

## Exit Criteria

1. Zero unresolved critical/high issues.
2. Reproducible security report and remediation log.
3. Deterministic emergency procedures with named owners and timed steps.

## Acceptance Checklist

- [ ] External review(s) completed
- [ ] All critical/high issues closed
- [ ] Remediation log complete with references
- [ ] Formal invariant evidence linked
- [ ] Formal evidence matrix gate passing
- [ ] Verifier governance history exported and published
- [ ] Drill evidence attached and signed off
- [ ] Final readiness review approved
