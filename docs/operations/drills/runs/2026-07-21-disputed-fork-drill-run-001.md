# Disputed Fork Drill Run 001

- Date: 2026-07-21
- Drill template: docs/operations/drills/disputed-fork-drill.md
- Mode: Tabletop with adversarial test evidence

## Owners
- Incident Commander: Local Protocol Operator
- Protocol Lead: Local Protocol Operator
- Exchange/Infra Liaison: Local Protocol Operator
- Community Comms: Local Protocol Operator

## Scenario
Two branches claim legitimacy after a contentious mandate outcome and fork-intent threshold event.

## Procedure Execution
1. Reviewed branch legitimacy checklist and objective onchain criteria.
2. Validated fork timing boundaries using adversarial test coverage:
   - registerForkIntent before passed state reverts
   - exact-threshold activation transitions to forked state
   - post-execution-window registration reverts
3. Confirmed branch-governor delay protections are already covered in the main EPBM suite.

## Results
- Legitimacy criteria remained deterministic under contentious conditions.
- Timing edge cases were covered by executable tests.
- Communication payload for canonical-branch statement drafted.

## Evidence
- Command: npm run test:security
- Result: pass
- Supporting tests: test/EPBM.adversarial.test.ts
- Follow-up actions: run this drill with external observer participants in staging
