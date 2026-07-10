# examples/ — mock test worknotes for `worknote-orchestrate`

These are **runnable fixtures** that drive the `worknote-orchestrate` skill (and, through it,
`research-memory`) end-to-end for realistic research workflows — **without any GPU, SLURM, or
wandb**. A tiny local mock scheduler (`bin/mockjob`) stands in for the real job system: `submit`
returns a job id, `status <id>` resolves that id to a state *without the submitter's context*, and
`collect <id>` returns a metric. Jobs finish in milliseconds and deterministically succeed, fail,
or hang.

They live in `examples/` rather than `tests/` because they double as **executable documentation**:
a human can walk any scenario by hand, or an agent session can run it end-to-end. A future
`tests/` harness can still call `bin/mockjob` and diff against each scenario's `EXPECTED.md`.

## Scenarios (partitioned by what they stress)

| Dir | Stresses | Key mechanics exercised |
|---|---|---|
| `scenario-A-fanout/` | **Classification + Mode A parallel fan-out** | fill-from-data vs needs-work; parallel agents; one BLOCKED→answered cycle (`skip dp=8`) |
| `scenario-B-reconcile/` | **Marker state machine + `status` reconciliation** | pre-seeded RUNNING/BLOCKED/blocked+answered; stale-claim ×2; orphaned-job; done-but-unwritten; status-never-writes; re-activation |
| `scenario-C-directives/` | **Hint directives** | `@dir:<workdir>` routing across two workdirs; `@memory`; `@run` |
| `scenario-D-human-edit/` | **Human-edit resilience** | mid-flight cancel (deleted marker), supersede (edited `task:`), lost-result safety |

Each scenario is self-contained: a worknote (`<Name>.md`), a pre-seeded memory store
(`<Name>.memory/`), one or more `workdir/`s to `cd` into, an `EXPECTED.md` spec, and
`setup.sh`/`reset.sh` (D also has `mutate.sh`).

## The mock scheduler — `bin/mockjob`

Emulates the SLURM-style contract the runbook's Monitor/Collect steps assume. State lives on disk
under `<memory-dir>/.mockjob/` (resolved via the fixed `./research-memory` symlink), keyed by job
id — so any session can resolve a job it never submitted.

```
mockjob submit --purpose "<t>" [--plan <name>] [--metric <f>]   # prints ONLY the job id
mockjob status <jobid>                                          # one token; unknown id → exit 3
mockjob collect <jobid>                                         # metric | not-ready(4) | reason(5)
mockjob reset | list                                           # harness/debug only
```

**Deterministic, memoryless plan mapping** (retries never change the outcome):

| plan | every `status` returns | drives |
|---|---|---|
| `fast-ok` | `finished` | happy path |
| `fail` | `failed` | BLOCKED path |
| `hang-running` | `running` | stale-claim (live-but-stuck) |
| *(no state file for the id)* | `unknown` (exit 3) | stale-claim (unresolvable id) |
| *(marker `job=pending`, never submitted)* | — | stale-claim (never submitted) |

A scenario's seeded `runbook.md` wires all three commands to `$MOCKJOB` = `../../bin/mockjob`
(relative to any scenario `workdir`) and encodes each config's plan in its `configs.md` key knobs.

## Run matrix

| Scenario | Setup | Invocation | Human input during run |
|---|---|---|---|
| A | `./setup.sh` | `/worknote-orchestrate <abs>/Fanout.md` | answer one batched blocker: `skip dp=8, note OOM` |
| B | `./setup.sh` | `... status` (pass 1), then `... Reconcile.md` (pass 2) | optional: answer #4 in pass-2 batch |
| C | `./setup.sh` | `/worknote-orchestrate <abs>/Directives.md` | none |
| D | `./setup.sh` → phase 1 → `./mutate.sh` → phase 2 | `/worknote-orchestrate <abs>/HumanEdit.md` (twice) | optional: answer the cancel-kill question |

See **`RUN_GUIDE.md`** for exact steps (including the sonnet cost note) and the manual by-hand walk.

## Cost — run on sonnet

The skills don't hardcode a model. To keep these cheap, run the **coordinator session on sonnet**
and instruct it to create every dispatched `general-purpose` Agent (placeholder-agents and
research-memory subagents) with `model: sonnet`. See `RUN_GUIDE.md` § "Running on sonnet".

## Reset

Every scenario's git-tracked fixtures ARE the canonical seed. `./reset.sh` runs
`git checkout -- <scenario>` and removes the untracked run artifacts (the `research-memory`
symlink and the `.mockjob/` state). Re-run `./setup.sh` to start fresh.

> **Never commit** the per-workdir `research-memory` symlink, its `git info/exclude` entry, or the
> `.mockjob/` state. `setup.sh` recreates all three per checkout; the repo `.gitignore` also
> covers the symlink and `.mockjob/` as a safety net.
