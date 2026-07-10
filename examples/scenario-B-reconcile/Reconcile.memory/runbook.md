# Runbook

<!-- MUTABLE, sectioned. Execution learnings for this project. -->
<!-- Add learnings under the matching section via `research-memory add-learning`. -->
<!-- Each learning carries a timestamp and, where relevant, an evidence pointer. -->

## Environment
- No GPU required — this project runs against the **mock scheduler** `mockjob`.
- `$MOCKJOB` = `../../bin/mockjob` (relative to this workdir; the scenario workdir is
  `examples/scenario-B-reconcile/workdir`). Invoke it from inside the workdir after `cd`.
- The mock scheduler keeps its state under `./research-memory/.mockjob/` (resolved via the
  fixed `./research-memory` symlink), so any session can resolve a job it did not submit.

## Submit
- One data-collection job per sweep point. Read the point's row in `configs.md`, take its
  `plan=<name>` knob, and submit:
  ```
  $MOCKJOB submit --purpose "sweep dp=<N>, collect throughput" --plan <plan-from-configs>
  ```
- `submit` prints ONLY the job id (e.g. `mock-0010`). Capture it verbatim into the `add-job`
  row and into the placeholder marker's `job=` field.

## Monitor
- Resolve a job id to status WITHOUT the submitter's context:
  ```
  $MOCKJOB status <jobid>
  ```
  Prints one token: `submitted` / `running` / `finished` / `failed`; an unresolvable id prints
  `unknown` (exit 3). This ledger-facing resolve is what backs stale-claim detection.

## Collect
- Once a job is `finished`, pull its metric:
  ```
  $MOCKJOB collect <jobid>
  ```
  On success prints one metric line (e.g. `throughput=1234.5 tok/s`, exit 0). If not ready yet
  prints `not-ready` (exit 4). If the job `failed`, prints the failure reason (exit 5) — turn
  that into a BLOCKED question, do NOT silently retry.

## Pitfalls
- A `RUNNING` marker whose job id resolves to `unknown`/`finished`/`failed` (or is still
  `job=pending` past the submit latency) is a **stale claim** — the ledger, not the marker, is
  authoritative. Resume or reassign; never assume it is live.
- A `collect` that exits non-zero with a failure reason means the job **failed** — record a
  blocker (`add-blocker`) and flip the marker to `BLOCKED`; never retry a `fail`-plan job hoping
  for a different outcome (the scheduler is deterministic/memoryless).
- A ledger-`running` job id with NO marker in the worknote is an **orphaned job** (a human
  deleted its marker) — a `status` scan flags it; only a planning scan may cancel it.
