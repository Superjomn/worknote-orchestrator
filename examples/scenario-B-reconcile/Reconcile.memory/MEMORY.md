# DP Reconcile Study — Research Memory Index

<!-- MUTABLE, rewritten in place. Keep this file ≤150 lines. -->
<!-- The only file main agents read routinely. Index + current ground truth only. -->
<!-- Every fact must carry a timestamp and an evidence pointer (job id, log path, dashboard URL). -->

## Current focus
- Reconciling a pre-dispatched dp sweep {2,4,8,16,32,64}: resolve stale claims, re-activate the
  answered blocker (#5), and write back the finished-but-unwritten point (#6).

## Validated conclusions
_(facts confirmed by evidence; each bullet ends with a pointer + timestamp)_
- dp=64 config `dp64` reaches 1400.0 tok/s — job mock-0006, 2026-07-09 → tasks/task-6.md.

## Reference configs
_(pointers to the current best / working configs; details live in configs.md)_
- validated dp64 → configs.md#dp64 (status: working)

## Pointers
- Configs ledger: `./configs.md`
- Runbook (how to submit/monitor/collect): `./runbook.md`
- Job ledger (append-only): `./jobs.md`
- Open blockers: `./blockers.md`
- Per-task files: `./tasks/task-<id>.md`
