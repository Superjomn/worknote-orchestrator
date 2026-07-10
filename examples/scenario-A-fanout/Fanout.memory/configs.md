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
| baseline | workdir | working | dp=1, bs=64, image=nano:0.3, plan=fast-ok | mock-0000, 2026-07-08 |
| dp2 | workdir | untested | dp=2, bs=64, image=nano:0.3, plan=fast-ok | — |
| dp4 | workdir | untested | dp=4, bs=64, image=nano:0.3, plan=fast-ok | — |
| dp8 | workdir | untested | dp=8, bs=64, image=nano:0.3, plan=fail | — |
