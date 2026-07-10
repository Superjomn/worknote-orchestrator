# Task #3 — sweep dp=8

<!-- L3 per-task working state. Read/written ONLY by the owner or restarter of #3. -->
<!-- Created lazily on first claim of #3. Detail lives here; only curated facts flow up. -->
<!-- Attempts are APPEND-ONLY. Working notes are mutable scratch. Outcome is filled once. -->

## Brief
- task: sweep dp=8, collect throughput
- workdir: examples/scenario-D-human-edit/workdir
- worknote: HumanEdit.md#3
- blockers: none

## Attempts
<!-- Append one `### Attempt N` section per dispatch. Never rewrite a prior attempt. -->

### Attempt 1 — 2026-07-09 09:00
- tried: submitted dp=8 sweep point with the validated recipe
- jobs: mock-0003
- outcome: succeeded — job finished, throughput=1250.0 tok/s
- next step: write the result back into the worknote (marker #3 may be edited by the human)

## Working notes
<!-- Mutable scratch: partial results, hypotheses, intermediate numbers. -->
- Job mock-0003 finished at 2026-07-09 09:18; metric throughput=1250.0 tok/s.

## Outcome
<!-- Filled ONCE, on completion. -->
- conclusion: dp=8 reaches 1250.0 tok/s (validated).
- promoted: configs.md#dp8 (working); MEMORY.md Validated-conclusions bullet; jobs.md result ptr.
