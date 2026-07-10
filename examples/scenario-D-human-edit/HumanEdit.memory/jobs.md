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
| 2026-07-09 09:00 | mock-0002 | sweep dp=4 | configs.md#dp4 | agent | running | — |
| 2026-07-09 09:00 | mock-0003 | sweep dp=8 | configs.md#dp8 | agent | running | — |
| 2026-07-09 09:18 | mock-0003 | sweep dp=8 | configs.md#dp8 | agent | finished | throughput=1250.0 tok/s |
