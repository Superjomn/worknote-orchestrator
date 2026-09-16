# Task #<id> — <short title>

<!-- L3 per-task state. Owner/restarter and coordinator read it; serialize updates. -->
<!-- Created on ID reservation, including fill-from-data tasks. Never delete to recycle an ID. -->
<!-- Active Attempt fields may be updated by its owner; closed Attempts are immutable. -->
<!-- Working notes hold late results/publication status. Final Outcome is filled once. -->

## Brief
- task: <the placeholder's inner text / approved strategy>
- workdir: <absolute target workdir>
- worknote: <absolute worknote path>#<id>
- context: <resolved `<<! ... >>` chain at first claim: block texts joined by ` | `, outermost → innermost; `none` if empty>
- blockers: <blocker ids raised by this task, or none>

## Attempts
<!-- Append one Attempt per dispatch; remove this example for an ID-only reservation. -->
<!-- Keep task/context/owner snapshots fixed; update active progress until closing it. -->

### Attempt 1 — <YYYY-MM-DD HH:MM>
- task: <approved task text for this dispatch>
- owner: <agent:session or tab:name>
- token: <unique attempt token from claimed marker>
- fingerprint: <scanner input fingerprint captured at dispatch>
- submission: <intent and runner correlation token recorded before submission, or none>
- context: <chain resolved for this dispatch, same ` | ` form (or `none`) — what `context-drift` compares against>
- tried: <what was attempted>
- jobs: <job ids submitted this attempt, or none>
- outcome: <active | succeeded | failed | blocked (blocker id) | cancelled | superseded — what happened>
- next step: <what the next attempt should do differently; dead ends to skip>

## Working notes
<!-- Mutable scratch: partial results, hypotheses, intermediate numbers. -->

## Outcome
<!-- Filled ONCE for current-task completion after promotion read-back, before publication. -->
- token: <originating attempt token>
- fingerprint: <validated input fingerprint>
- conclusion: <final result — conclusions only>
- promoted: <what flowed up and where: configs.md#<id> / runbook §<section> / MEMORY.md bullet / none / FAILED (reason)>
