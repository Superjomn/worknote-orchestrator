# Task #<id> — <short title>

<!-- L3 per-task working state. Read/written ONLY by the owner or restarter of #<id>. -->
<!-- Created lazily on first claim of #<id>. Detail lives here; only curated facts flow up. -->
<!-- Attempts are APPEND-ONLY. Working notes are mutable scratch. Outcome is filled once. -->

## Brief
- task: <the placeholder's inner text / approved strategy>
- workdir: <absolute target workdir>
- worknote: <absolute worknote path>#<id>
- blockers: <blocker ids raised by this task, or none>

## Attempts
<!-- Append one `### Attempt N` section per dispatch. Never rewrite a prior attempt. -->

### Attempt 1 — <YYYY-MM-DD HH:MM>
- tried: <what was attempted>
- jobs: <job ids submitted this attempt, or none>
- outcome: <succeeded | failed | blocked (blocker id) — what happened>
- next step: <what the next attempt should do differently; dead ends to skip>

## Working notes
<!-- Mutable scratch: partial results, hypotheses, intermediate numbers. -->

## Outcome
<!-- Filled ONCE, on completion. -->
- conclusion: <final result — conclusions only>
- promoted: <what flowed up and where: configs.md#<id> / runbook §<section> / MEMORY.md bullet>
