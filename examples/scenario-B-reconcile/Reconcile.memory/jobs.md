# Jobs Ledger

<!-- APPEND-ONLY. Never rewrite or reorder rows. -->
<!-- One row per job. A status change appends a NEW row referencing the same job id. -->
<!-- Job ids must be resolvable to status without the submitting agent's context. -->
<!-- This ledger — not the placeholder marker — is authoritative for job liveness. -->
<!-- status ∈ submitted / running / finished / failed / cancelled. -->
<!-- "unknown" is not a stored status — it means the job id could not be resolved to any of the above -->
<!-- (e.g. scheduler forgot it); stale-claim logic treats an unresolvable id the same as finished/failed. -->

| timestamp | job id | purpose | config ref | owner | status | result ptr |
|---|---|---|---|---|---|---|
| 2026-07-09 09:00 | mock-0001 | sweep dp=2 | configs.md#dp2 | agent | running | — |
| 2026-07-09 09:00 | mock-0002 | sweep dp=4 | configs.md#dp4 | agent | submitted | — |
| 2026-07-09 09:05 | mock-0006 | sweep dp=64 | configs.md#dp64 | agent | running | — |
| 2026-07-09 09:20 | mock-0006 | sweep dp=64 | configs.md#dp64 | agent | finished | throughput=1400.0 tok/s |
| 2026-07-09 09:30 | mock-0009 | sweep dp=128 | configs.md#dp128 | agent | running | — |
