# Task #6 — sweep dp=64

<!-- L3 per-task working state. Read/written ONLY by the owner or restarter of #6. -->
<!-- Created lazily on first claim of #6. Detail lives here; only curated facts flow up. -->
<!-- Attempts are APPEND-ONLY. Working notes are mutable scratch. Outcome is filled once. -->

## Brief
- task: sweep dp=64, collect throughput
- workdir: examples/scenario-B-reconcile/workdir
- worknote: Reconcile.md#6
- blockers: none

## Attempts
<!-- Append one `### Attempt N` section per dispatch. Never rewrite a prior attempt. -->

### Attempt 1 — 2026-07-09 09:05
- tried: submitted dp=64 sweep point with the validated recipe
- jobs: mock-0006
- outcome: succeeded — collected throughput=1400.0 tok/s
- next step: none; write the result back into the worknote (marker #6 still present)

## Working notes
<!-- Mutable scratch: partial results, hypotheses, intermediate numbers. -->
- Job mock-0006 finished at 2026-07-09 09:20; metric throughput=1400.0 tok/s.

## Outcome
<!-- Filled ONCE, on completion. -->
- conclusion: dp=64 reaches 1400.0 tok/s (validated).
- promoted: configs.md#dp64 (working); MEMORY.md Validated-conclusions bullet.
