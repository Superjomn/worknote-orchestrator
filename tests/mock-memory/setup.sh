#!/usr/bin/env bash
# setup.sh <case-id> <scratch-dir>
#
# Builds a per-case research-memory fixture under <scratch-dir>/research-memory/
# from skills/research-memory/templates/. Idempotent: the store is wiped and
# rebuilt on every run. A byte-for-byte snapshot is left in
# <scratch-dir>/research-memory.orig/ so assert.sh can diff refusal cases.
#
# Case-id -> fixture builder map:
#   P1 P3 P4 P5 -> fresh            (pristine store + tasks/task-1.md)
#   J1 J2       -> fresh-jobs       (pristine store, no tasks/ needed — jobs.md/configs.md focus)
#   P2          -> promoted         (one existing Validated-conclusions bullet -> task-1)
#   C1 C3       -> config-untested  (configs.md baseline-v2 @ untested + template example)
#   C2 C4       -> config-working   (configs.md baseline-v2 @ working, mirrored in MEMORY.md)
#   C5          -> config-evidence-failed (configs baseline-v2 @ untested + jobs.md srun-500 failed)
#   L1          -> near-cap         (MEMORY.md padded to exactly 150 lines)
#   D1          -> drifted          (tasks/task-2.md Outcome claims promotion, MEMORY.md has none)
#   W1          -> worknote         (fresh store + tasks/task-1.md + Scratch.md RUNNING#1 marker)
set -euo pipefail

CASE="${1:?usage: setup.sh <case-id> <scratch-dir>}"
SCRATCH="${2:?usage: setup.sh <case-id> <scratch-dir>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES="$SCRIPT_DIR/../../skills/research-memory/templates"
[ -d "$TEMPLATES" ] || { echo "FATAL: templates dir not found: $TEMPLATES" >&2; exit 2; }

mkdir -p "$SCRATCH"
STORE="$SCRATCH/research-memory"
rm -rf "$STORE" "$SCRATCH/research-memory.orig"
rm -f "$SCRATCH/refusal.txt"   # refusal-case capture lives in $SCRATCH, not the store
mkdir -p "$STORE/tasks"

copy_templates() {
  local f
  for f in MEMORY.md configs.md runbook.md jobs.md blockers.md; do
    cp "$TEMPLATES/$f" "$STORE/$f"
  done
  # Stamp the project name into MEMORY.md's heading (init would do this).
  sed -i 's/^# <Project> — Research Memory Index/# Mock — Research Memory Index/' "$STORE/MEMORY.md"
}

# make_task <id> — create tasks/task-<id>.md from task.md with the id substituted.
make_task() {
  local id="$1"
  sed "s/<id>/$id/g" "$TEMPLATES/task.md" > "$STORE/tasks/task-$id.md"
}

# ---- MEMORY.md variants -----------------------------------------------------

# write_memory_promoted — MEMORY.md with one real Validated-conclusions bullet
# pointing at tasks/task-1.md (template example bullet already removed = clean).
write_memory_promoted() {
  cat > "$STORE/MEMORY.md" <<'EOF'
# Mock — Research Memory Index

<!-- MUTABLE, rewritten in place. Keep this file ≤150 lines. -->
<!-- The only file main agents read routinely. Index + current ground truth only. -->
<!-- Every fact must carry a timestamp and an evidence pointer (job id, log path, dashboard URL). -->

## Current focus
_(what the project is actively working on right now — 1–5 bullets)_

## Validated conclusions
_(facts confirmed by evidence; each bullet ends with a pointer + timestamp)_
- baseline reaches 1000 tok/s — job srun-100, 2026-07-01 → tasks/task-1.md

## Reference configs
_(pointers to the current best / working configs; details live in configs.md)_
- _(e.g. "working baseline → configs.md#baseline-v2 (status: working)")_

## Pointers
- Configs ledger: `./configs.md`
- Runbook (how to submit/monitor/collect): `./runbook.md`
- Job ledger (append-only): `./jobs.md`
- Open blockers: `./blockers.md`
- Per-task files: `./tasks/task-<id>.md`
EOF
}

# write_memory_config_working — Reference configs already mirrors baseline-v2
# at working (template example removed = clean). For the C2 replace case.
write_memory_config_working() {
  cat > "$STORE/MEMORY.md" <<'EOF'
# Mock — Research Memory Index

<!-- MUTABLE, rewritten in place. Keep this file ≤150 lines. -->
<!-- The only file main agents read routinely. Index + current ground truth only. -->
<!-- Every fact must carry a timestamp and an evidence pointer (job id, log path, dashboard URL). -->

## Current focus
_(what the project is actively working on right now — 1–5 bullets)_

## Validated conclusions
_(facts confirmed by evidence; each bullet ends with a pointer + timestamp)_
- _(e.g. "baseline config X reaches 1200 tok/s — job srun-8812345, wandb/run/abc, 2026-07-09 → tasks/task-3.md")_

## Reference configs
_(pointers to the current best / working configs; details live in configs.md)_
- baseline-v2 → configs.md#baseline-v2 (status: working)

## Pointers
- Configs ledger: `./configs.md`
- Runbook (how to submit/monitor/collect): `./runbook.md`
- Job ledger (append-only): `./jobs.md`
- Open blockers: `./blockers.md`
- Per-task files: `./tasks/task-<id>.md`
EOF
}

# write_memory_near_cap — pad MEMORY.md to EXACTLY 150 lines with synthetic
# promoted bullets, each carrying a `→ tasks/task-N.md` pointer. A subsequent
# promote must curate (compress oldest) to stay ≤150 without dropping pointers.
write_memory_near_cap() {
  local top bottom target t_lines b_lines need i
  target=150
  top="$STORE/.top"
  bottom="$STORE/.bottom"
  cat > "$top" <<'EOF'
# Mock — Research Memory Index

<!-- MUTABLE, rewritten in place. Keep this file ≤150 lines. -->
<!-- The only file main agents read routinely. Index + current ground truth only. -->
<!-- Every fact must carry a timestamp and an evidence pointer (job id, log path, dashboard URL). -->

## Current focus
- promote under near-cap conditions

## Validated conclusions
_(facts confirmed by evidence; each bullet ends with a pointer + timestamp)_
EOF
  cat > "$bottom" <<'EOF'

## Reference configs
_(pointers to the current best / working configs; details live in configs.md)_
- baseline-v2 → configs.md#baseline-v2 (status: working)

## Pointers
- Configs ledger: `./configs.md`
- Runbook (how to submit/monitor/collect): `./runbook.md`
- Job ledger (append-only): `./jobs.md`
- Open blockers: `./blockers.md`
- Per-task files: `./tasks/task-<id>.md`
EOF
  t_lines=$(wc -l < "$top")
  b_lines=$(wc -l < "$bottom")
  need=$(( target - t_lines - b_lines ))
  [ "$need" -gt 0 ] || { echo "FATAL: near-cap math wrong (need=$need)" >&2; exit 2; }
  cp "$top" "$STORE/MEMORY.md"
  for i in $(seq 1 "$need"); do
    printf -- '- synthetic conclusion %02d holds — job srun-%03d, 2026-07-%02d → tasks/task-%d.md\n' \
      "$i" "$i" "$(( (i % 28) + 1 ))" "$i" >> "$STORE/MEMORY.md"
  done
  cat "$bottom" >> "$STORE/MEMORY.md"
  rm -f "$top" "$bottom"
}

# ---- configs.md variants ----------------------------------------------------

# write_configs_untested — template example row PLUS a real baseline-v2 row at
# untested. The example row was deliberately left (manual seeding bypassed the
# template-hygiene rule); the C1 real write must delete it.
write_configs_untested() {
  cat > "$STORE/configs.md" <<'EOF'
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

| id/path | workdir | status | key knobs | evidence |
|---|---|---|---|---|
| _(e.g. baseline-v2 / configs/baseline.yaml)_ | _(wt-dp-sweep)_ | _(untested)_ | _(dp=4, bs=64, image=nano:0.3)_ | _(srun-8812345, wandb/run/abc, 2026-07-09)_ |
| baseline-v2 | wt-mock | untested | dp=4, bs=64 | srun-500, 2026-07-05 |
EOF
}

# write_configs_working — baseline-v2 at working, template example already
# removed (clean store). For the C2 working->superseded case.
write_configs_working() {
  cat > "$STORE/configs.md" <<'EOF'
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

| id/path | workdir | status | key knobs | evidence |
|---|---|---|---|---|
| baseline-v2 | wt-mock | working | dp=4, bs=64 | srun-500, 2026-07-05 |
EOF
}

# write_configs_untested_clean — baseline-v2 at untested, NO template example row.
write_configs_untested_clean() {
  cat > "$STORE/configs.md" <<'EOF'
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

| id/path | workdir | status | key knobs | evidence |
|---|---|---|---|---|
| baseline-v2 | wt-mock | untested | dp=4, bs=64 | srun-500 (attempted) |
EOF
}

# write_jobs_srun500_failed — jobs.md with a failed row for srun-500 (the run a
# later `→ working` would illegitimately cite). Template example row kept clean.
write_jobs_srun500_failed() {
  cat > "$STORE/jobs.md" <<'EOF'
# Jobs Ledger

<!-- APPEND-ONLY. Never rewrite or reorder rows. -->
<!-- One row per job. A status change appends a NEW row referencing the same job id. -->
<!-- Job ids must be resolvable to status without the submitting agent's context. -->
<!-- This ledger — not the placeholder marker — is authoritative for job liveness. -->
<!-- status ∈ submitted / running / finished / failed / cancelled. -->
<!-- "unknown" is not a stored status — it means the job id could not be resolved to any of the above -->
<!-- (e.g. scheduler forgot it); stale-claim logic treats an unresolvable id the same as finished/failed. -->

| timestamp | job id | purpose | config ref | owner | status | result ptr |
|---|---|---|---|---|---|---|
| 2026-07-05 10:00 | srun-500 | verify baseline-v2 | configs.md#baseline-v2 | tab:mock | submitted | — |
| 2026-07-05 10:40 | srun-500 | verify baseline-v2 | configs.md#baseline-v2 | tab:mock | failed | /logs/500.txt (OOM) |
EOF
}

# ---- builders ---------------------------------------------------------------

build_fresh() {
  copy_templates
  make_task 1
}

build_config_evidence_failed() {
  copy_templates
  write_configs_untested_clean
  write_jobs_srun500_failed
}

build_promoted() {
  copy_templates
  write_memory_promoted
  make_task 1
}

build_config_untested() {
  copy_templates
  write_configs_untested
}

build_config_working() {
  copy_templates
  write_configs_working
  write_memory_config_working
}

build_near_cap() {
  copy_templates
  write_memory_near_cap
  make_task 90
  grep -oE '→ tasks/task-[0-9]+\.md' "$STORE/MEMORY.md" | sort -u > "$SCRATCH/pointers.orig"
}

build_drifted() {
  copy_templates
  make_task 2
  # task-2 Outcome CLAIMS a promotion that MEMORY.md does not carry -> drift.
  sed -i 's|^- conclusion:.*|- conclusion: drift test — Outcome claims promotion, MEMORY.md has none|' "$STORE/tasks/task-2.md"
  sed -i 's|^- promoted:.*|- promoted: MEMORY.md bullet (2026-07-09)|' "$STORE/tasks/task-2.md"
  cat > "$SCRATCH/Scratch.md" <<'EOF'
# Scratch worknote

Task #2 completed (result recorded in research-memory/tasks/task-2.md).
EOF
}

build_worknote() {
  copy_templates
  make_task 1
  cat > "$SCRATCH/Scratch.md" <<'EOF'
# Scratch worknote

## Result
<<RUNNING#1 owner=tab:mock job=srun-777 since=2026-07-09 task: mock promote read-back>>
EOF
}

case "$CASE" in
  P1|P3|P4|P5) build_fresh ;;
  J1|J2)       build_fresh ;;
  P2)          build_promoted ;;
  C1|C3)       build_config_untested ;;
  C2|C4)       build_config_working ;;
  C5)          build_config_evidence_failed ;;
  L1)          build_near_cap ;;
  D1)          build_drifted ;;
  W1)          build_worknote ;;
  *) echo "FATAL: unknown case-id '$CASE'" >&2; exit 2 ;;
esac

# Byte-for-byte snapshot for diff-based (refusal / no-mirror) assertions.
cp -r "$STORE" "$SCRATCH/research-memory.orig"

echo "setup $CASE done — store at $STORE (snapshot: $SCRATCH/research-memory.orig)"
