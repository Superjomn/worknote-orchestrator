# worknote-orchestrator

A Claude Code plugin for **worknote-powered parallel job management**. It pairs a shared, machine-facing research memory with a placeholder orchestrator so that a human worknote can be filled by running real jobs across many parallel tabs and agents — with the human interrupted **once** per round, not N times.

## What & why

Research and engineering work is a loop run many times in parallel: submit a long job, watch/fix/rerun, distill the outcome into a **human-owned worknote**. Across many Claude tabs (each in its own git worktree) this breaks down — no shared ground truth, manual distillation, and N scattered human interrupts. This plugin fixes that with a **two-artifact split**:

- **Worknote** — human-facing, conclusion-only, human-owned. AI contributes only through `<<...>>` placeholders.
- **Shared memory** — agent-facing, evidence-rich, strictly formatted: configs, runbook, job ledger, blockers. The only cross-session channel.

Two skills:

- **`research-memory`** — lifecycle for the shared store beside a worknote (`init`, `link`, `task-note`, `add-job`, `update-config-status`, `add-learning`, `add-blocker`, `answer-blocker`, `show-summary`). All writes go through subagents to keep the main context lean.
- **`worknote-orchestrate`** — scans the worknote, stamps each placeholder with a stable `#id`, classifies it as *fill-from-data* or *needs-work*, and runs the needs-work ones either as **coordinator-driven parallel agents** (Mode A) or a **human-driven tab** (Mode B — which, on a never-planned worknote, stamps just its own placeholder on claim). State lives in the worknote itself as `<<RUNNING#id ...>>` / `<<BLOCKED#id ...>>` markers, so the worknote is the dashboard. The human may edit/reword/delete placeholders mid-flight — agents tolerate it (memory is ground truth; the worknote write is best-effort). `/worknote-orchestrate <worknote> status` prints a read-only reconciled dashboard. Per-task restartable state lives in `tasks/task-<id>.md` so a re-dispatch resumes instead of re-deriving. Layers on `complete-report`.

## Install

```
/plugin marketplace add Superjomn/worknote-orchestrator
/plugin install worknote-orchestrator@worknote-orchestrator
```

## Quickstart

1. **init** — beside your worknote `MyStudy.md`, create the shared store:
   ```
   /research-memory init /path/to/MyStudy.md
   ```
   This creates `MyStudy.memory/` with `MEMORY.md`, `configs.md`, `runbook.md`, `jobs.md`, `blockers.md`.

2. **link** — in each participating worktree/tab, symlink the store to a fixed path:
   ```
   /research-memory link
   ```
   Creates `./research-memory -> .../MyStudy.memory/` and registers it in git's `info/exclude` (worktree-safe via `git rev-parse --git-path`, so it works in both a normal repo and a linked worktree).

3. **orchestrate** — fill the worknote's placeholders, running jobs where needed:
   ```
   /worknote-orchestrate /path/to/MyStudy.md          # whole file (coordinator, Mode A)
   /worknote-orchestrate /path/to/MyStudy.md #3        # one placeholder (human tab, Mode B)
   ```

Canary-then-fan-out: bring up one config interactively (Mode B) until it's `working` in `configs.md`, then fan out the rest as parallel Mode A agents.

## Design

The two skills are self-documenting: `worknote-orchestrate` covers the two-artifact split, the orchestrator modes, roles, and the end-to-end flow; `research-memory` covers the shared-memory layer and its three-level hierarchy (L1 index / L2 ledgers / L3 per-task files).

## License

Author: Chunwei Yan.
