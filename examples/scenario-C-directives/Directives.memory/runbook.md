# Runbook

<!-- MUTABLE, sectioned. Execution learnings for this project. -->
<!-- Add learnings under the matching section via `research-memory add-learning`. -->
<!-- Each learning carries a timestamp and, where relevant, an evidence pointer. -->

## Environment
- No GPU required — this project runs against the **mock scheduler** `mockjob`.
- This project spans MULTIPLE workdirs: `workdir-alpha`, `workdir-beta`, and the default
  invocation `workdir`. Each has its own `./research-memory` symlink pointing at the SAME
  `Directives.memory/` store (fixed relative path → shared ground truth).
- `$MOCKJOB` = `../../bin/mockjob` (relative to any of these workdirs; they all live at
  `examples/scenario-C-directives/workdir*`, two levels above `examples/bin`). Invoke it from
  inside the target workdir after `cd`.
- The mock scheduler keeps its state under `./research-memory/.mockjob/` (resolved via the fixed
  `./research-memory` symlink), so any session can resolve a job it did not submit. Because all
  workdirs share one memory store, they share one `.mockjob/` ledger too.

## Submit
- One data-collection job per batch-size point. Read the point's row in `configs.md`, take its
  `plan=<name>` knob, `cd` into the point's assigned workdir (per its `@dir:` directive), and submit:
  ```
  $MOCKJOB submit --purpose "measure latency at bs=<N>" --plan <plan-from-configs>
  ```
- `submit` prints ONLY the job id (e.g. `mock-0007`). Capture it verbatim into the `add-job`
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
- A `collect` that exits non-zero with a failure reason means the job **failed** — record a
  blocker (`add-blocker`) and flip the marker to `BLOCKED`; never retry a `fail`-plan job hoping
  for a different outcome (the scheduler is deterministic/memoryless).
- A marker left at `job=pending` past the submit latency means the claiming session never
  submitted — treat it as a **stale claim**, not a live job.
- `@dir:` names a repo-relative path; `cd` to it (setup.sh prints the absolute base) before submit
  so the job's `./research-memory` resolves to the shared store.
