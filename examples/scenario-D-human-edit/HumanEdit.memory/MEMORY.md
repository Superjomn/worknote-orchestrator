# DP Sweep — Live-Edit Resilience — Research Memory Index

<!-- MUTABLE, rewritten in place. Keep this file ≤150 lines. -->
<!-- The only file main agents read routinely. Index + current ground truth only. -->
<!-- Every fact must carry a timestamp and an evidence pointer (job id, log path, dashboard URL). -->

## Current focus
- Three dp points (#1 dp=2, #2 dp=4, #3 dp=8) dispatched and RUNNING; reconciling after a live
  human edit that cancels #1, re-scopes #2 (bs=128), and deletes #3's marker post-finish.

## Validated conclusions
_(facts confirmed by evidence; each bullet ends with a pointer + timestamp)_
- dp=8 config `dp8` reaches 1250.0 tok/s — job mock-0003, 2026-07-09 → tasks/task-3.md.

## Reference configs
_(pointers to the current best / working configs; details live in configs.md)_
- validated dp8 → configs.md#dp8 (status: working)

## Pointers
- Configs ledger: `./configs.md`
- Runbook (how to submit/monitor/collect): `./runbook.md`
- Job ledger (append-only): `./jobs.md`
- Open blockers: `./blockers.md`
- Per-task files: `./tasks/task-<id>.md`
