# Production-Network Stage

## Goal
Prove real-world resilience under social and economic stress.

## Required Workstreams

1. Controlled rollout
- Launch in a live test ecosystem with real participants and explicit incentives.
- Run at least N full governance cycles before promotion.

2. Parameter stress campaigns
- Use capture simulation and frontier sweeps.
- Publish safe operating envelope and rationale.

3. Governance legitimacy exercises
- Run contentious-fork simulations with comms/client/infra coordination.
- Publish outcomes and decision criteria.
- Export legitimacy packet with objective onchain evidence.
- Command: `npm run export:fork-legitimacy -- --epbm <epbmAddress> --mandate-id <id>`

4. Policy hardening
- Verifier admission/removal constitution.
- Transparent dispute process.
- Incident postmortem template and publication SLA.

5. Public drill accountability
- Run drills with external participants and witness attestations.
- Use witness template: `docs/operations/drills/runs/WITNESS_ATTESTATION_TEMPLATE.md`

## Exit Criteria

1. Stable operation over multiple governance cycles.
2. No unhandled incidents in adversarial drills.
3. Published governance constitution, postmortem template, and parameter policy.
4. Published fork-legitimacy packets for contentious events.
5. Three consecutive externally witnessed drill cycles.

## Acceptance Checklist

- [ ] Rollout cohorts defined
- [ ] Incentive plan documented
- [ ] Safe parameter envelope published
- [ ] Legitimacy drill outputs published
- [ ] Fork legitimacy packet exporter used for contentious scenarios
- [ ] Governance constitution approved
- [ ] Incident template and SLA active
- [ ] External witness attestations attached for public drills
