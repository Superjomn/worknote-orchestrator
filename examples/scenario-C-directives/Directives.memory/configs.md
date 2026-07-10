# Configs

<!-- MUTABLE table, rewritten in place. One row per configuration/recipe. -->
<!-- Every row MUST carry an evidence pointer (job id, dashboard link, log path). -->

## Status legend

- `untested` — created/edited, not yet run to a verdict.
- `working` — a job succeeded and the result was verified. Safe to parallelize (Mode A).
- `failed` — a job with this config failed.
- `superseded` — replaced by a better validated config (link to the successor).

Status state machine:

```
untested --> working    (job succeeded, verified)
untested --> failed      (job failed)
failed   --> untested    (config edited)
working  --> failed      (a validated config regresses)
working  --> superseded  (better config validated)
```

## Table

<!-- The `plan=` knob names the mock scheduler outcome for this config (see runbook). -->

| id/path | workdir | status | key knobs | evidence |
|---|---|---|---|---|
| baseline | workdir | working | bs=16, image=nano:0.3, plan=fast-ok | mock-0000, 2026-07-08 |
| bs32 | workdir-alpha | untested | bs=32, image=nano:0.3, plan=fast-ok | — |
| bs64 | workdir-beta | untested | bs=64, image=nano:0.3, plan=fast-ok | — |
| bs128 | workdir | untested | bs=128, image=nano:0.3, plan=fast-ok | — |
