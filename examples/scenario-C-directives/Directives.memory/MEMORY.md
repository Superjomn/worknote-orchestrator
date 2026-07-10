# Batch-Size Latency Study — Research Memory Index

<!-- MUTABLE, rewritten in place. Keep this file ≤150 lines. -->
<!-- The only file main agents read routinely. Index + current ground truth only. -->
<!-- Every fact must carry a timestamp and an evidence pointer (job id, log path, dashboard URL). -->

## Current focus
- Measuring latency at bs ∈ {32, 64, 128}, each point pinned to a specific workdir via `@dir:`.

## Validated conclusions
_(facts confirmed by evidence; each bullet ends with a pointer + timestamp)_
- Baseline config `baseline` (bs=16, image=nano:0.3) is the best validated point so far at 1400.0 tok/s — job mock-0000, 2026-07-08 → configs.md#baseline.

## Reference configs
_(pointers to the current best / working configs; details live in configs.md)_
- working baseline → configs.md#baseline (status: working)

## Pointers
- Configs ledger: `./configs.md`
- Runbook (how to submit/monitor/collect): `./runbook.md`
- Job ledger (append-only): `./jobs.md`
- Open blockers: `./blockers.md`
- Per-task files: `./tasks/task-<id>.md`
