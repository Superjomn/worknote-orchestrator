# Jobs Ledger

<!-- APPEND-ONLY. Never rewrite or reorder rows. -->
<!-- One row per observed job state. A status change appends a NEW row referencing the same job id. -->
<!-- Job ids must be resolvable to status without the submitting agent's context. -->
<!-- Latest row per job is its last observed state; verify current liveness when needed. -->
<!-- Deleting/changing a marker does not prove a job was cancelled. -->
<!-- status ∈ submitted / running / finished / failed / cancelled. -->
<!-- A scancelled/released pool reservation is recorded as `cancelled` (release reason in result ptr); `released` is not a status. -->
<!-- "unknown" is not a stored status — it means the job id could not be resolved to any of the above -->
<!-- (e.g. scheduler forgot it); unresolved liveness is not proof of termination. -->

<!-- For orchestrated jobs, purpose includes task ID and attempt token on every row. -->

| timestamp | job id | purpose | config ref | owner | status | result ptr |
|---|---|---|---|---|---|---|
| _(2026-07-09 14:20)_ | _(srun-8812345)_ | _(sweep dp=4)_ | _(configs.md#baseline-v2)_ | _(tab:duckling-pie)_ | _(submitted)_ | _(—)_ |
