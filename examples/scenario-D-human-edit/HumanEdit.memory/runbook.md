# Runbook

<!-- MUTABLE, sectioned. Execution learnings for this project. -->
<!-- Add learnings under the matching section via `research-memory add-learning`. -->
<!-- Each learning carries a timestamp and, where relevant, an evidence pointer. -->

## Environment
- No GPU required — this project runs against the **mock scheduler** `mockjob`.
- `$MOCKJOB` = `../../bin/mockjob` (relative to this workdir; the scenario workdir is
  `examples/scenario-D-human-edit/workdir`). Invoke it from inside the workdir after `cd`.
- The mock scheduler keeps its state under `./research-memory/.mockjob/` (resolved via the
  fixed `./research-memory` symlink), so any session can resolve a job it did not submit.

## Submit
- One data-collection job per sweep point. Read the point's row in `configs.md`, take its
  `plan=<name>` knob, and submit:
  ```
  $MOCKJOB submit --purpose "sweep dp=<N>, collect throughput" --plan <plan-from-configs>
  ```
- `submit` prints ONLY the job id (e.g. `mock-0004`). Capture it verbatim into the `add-job`
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
  prints `not-ready` (exit 4). If the job `failed`, prints the failure reason (exit 5).

## Pitfalls
- **Cancel = deleted marker.** A ledger-`running` job whose marker vanished is cancelled: a
  planning scan appends a `cancelled` jobs.md row; it may OFFER to kill the job in the batched
  question round but NEVER auto-kills silently.
- **Supersede = edited `task:`.** If a RUNNING marker's `task:` text drifts from the dispatch in
  jobs.md, append a `cancelled`/superseded row for the old dispatch and re-dispatch `#id` with the
  new text (a fresh Attempt).
- **Results are never lost.** If your marker is gone at write time, still record everything in
  memory (add-job result ptr, task-file Outcome) and return `#id done (worknote not updated:
  marker missing)`.
