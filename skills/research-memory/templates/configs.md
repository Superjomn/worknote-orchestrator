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
working  --> superseded  (better config validated)
```

## Table

| id/path | workdir | status | key knobs | evidence |
|---|---|---|---|---|
| _(e.g. baseline-v2 / configs/baseline.yaml)_ | _(wt-dp-sweep)_ | _(untested)_ | _(dp=4, bs=64, image=nano:0.3)_ | _(srun-8812345, wandb/run/abc, 2026-07-09)_ |
