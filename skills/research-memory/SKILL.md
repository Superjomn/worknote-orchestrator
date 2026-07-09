---
name: research-memory
description: "Lifecycle for a shared, machine-facing research memory that sits next to a human worknote — the ground-truth store (configs, runbook, job ledger, blockers) for all sub-project sessions. All writes are dispatched to subagents to keep the main context lean. TRIGGER when: user says research-memory init/link/add-job/update-config-status/add-learning/show-summary, /research-memory, \"research memory\", \"shared worknote memory\", or wants to record a job/config/learning/blocker beside a worknote."
author: Chunwei Yan
version: 0.1.0
user_invocable: true
---

# research-memory — Shared Project Memory

## Purpose

`research-memory` maintains the **machine-facing ground truth** that sits beside a human worknote. It is the *memory* half of the two-artifact split:

- **Worknote** = human-facing, conclusion-only, human-owned prose and structure.
- **Shared memory** (this skill) = agent-facing, evidence-rich, strictly formatted facts, configs, ledgers, and learnings — the only cross-session communication channel for a project.

Every participating tab/worktree reaches the same store at a fixed relative path `./research-memory/`. It is consumed by the [[worknote-orchestrate]] skill, whose placeholder-agents read `./research-memory/MEMORY.md` and record everything they do via this skill's actions.

## Memory location & sharing

Memory lives **next to the worknote**, in a sibling directory named after it:

```
<worknote-dir>/
  MyStudy.md               # the human worknote
  MyStudy.memory/          # this store
    MEMORY.md  configs.md  runbook.md  jobs.md  blockers.md
```

Each participating working directory gets a symlink so any session reaches ground truth at a fixed path:

```
<workdir>/research-memory -> <worknote-dir>/MyStudy.memory/
```

- The symlink is registered in the workdir's **`.git/info/exclude`**, **never** `.gitignore`. Memory sharing is a local workflow concern, not a repo property — putting it in `.gitignore` would leak it into the tracked repo.
- `link` is per-workdir: run it once in each tab/worktree that participates.

## Files & mutability

| File | Mutability | Contents |
|---|---|---|
| `MEMORY.md` | Mutable, rewritten in place, **≤150 lines** | Index + current ground truth: validated conclusions, pointers to reference/working configs, current focus. The only file main agents read routinely. |
| `configs.md` | Mutable table | Status of each config/recipe: id or path, owning workdir, status, key knobs, evidence pointer. |
| `runbook.md` | Mutable, sectioned | Execution learnings: Environment / Submit / Monitor / Collect / Pitfalls. |
| `jobs.md` | **Append-only ledger** | One row per job: timestamp, id, purpose, config ref, owner, status, result pointer. Status updates **append a new row** referencing the job id; never rewrite or reorder. |
| `blockers.md` | Append-only entries, mutable `Answer:` only | Open questions for the human: id, timestamp, workdir, placeholder ref, Question, Evidence, `Answer:`. |

`configs.md` status state machine:

```
untested --> working    (job succeeded, verified)
untested --> failed      (job failed)
failed   --> untested    (config edited)
working  --> superseded  (better config validated)
```

> A config marked `working` in `configs.md` is the signal that a recipe is safe to parallelize (Mode A in [[worknote-orchestrate]]). Memory quality directly buys parallelism.

## Context-saving contract (CRITICAL)

Inherited from the `verl-worknote` skill. The point is to keep the **main agent's context lean** while memory files grow:

- **All mutating actions** (`init`, `link`, `add-job`, `update-config-status`, `add-learning`) MUST be dispatched to a subagent via the `Agent` tool. The main agent never loads the full file to mutate it.
- **Main agents do only bounded reads**: `MEMORY.md` (≤150 lines) directly via `Read`; anything larger goes through a read subagent that returns only the answer.
- **Mutable tables vs append-only ledgers**: `MEMORY.md`, `configs.md`, and `runbook.md` sections are rewritten in place; `jobs.md` and `blockers.md` entries are append-only (append new rows/entries; the only in-place edit permitted on an append-only file is filling a blocker's `Answer:`).
- **Every fact carries a timestamp and an evidence pointer** (job id, log path, dashboard URL). A claim without evidence does not belong in memory — if the schema can't be filled, the fact isn't ready to record.
- **One topic per file** minimizes concurrent-write collisions across tabs. Strict entry/row schemas (facts and tables, not prose dumps) keep the rare cross-tab merge trivial.
- Subagents MUST return a **≤3-line** confirmation of the form `<action> done — <one-line diff hint>`. They MUST NOT echo file bodies (except `show-summary`, where the requested content IS the return, though `show-summary` is a direct read, not a dispatch).

## Actions

| Action | Dispatch | Effect |
|---|---|---|
| `init <worknote-path>` | Subagent | Create `<Worknote-Name>.memory/` beside the worknote and copy the five template files into it. |
| `link` | Subagent | Create `./research-memory` symlink in the current workdir + add it to `.git/info/exclude`. |
| `add-job <fields>` | Subagent | Append one row to `jobs.md`. |
| `update-config-status <id> <status>` | Subagent | Update the row for `<id>` in `configs.md` (evidence pointer required). |
| `add-learning <text>` | Subagent | Add `<text>` to `runbook.md` under the matching section. |
| `show-summary` | Main (direct `Read`, limit ~150) | Bounded direct read of `MEMORY.md`. |

`init` copies templates from `${CLAUDE_PLUGIN_ROOT}/skills/research-memory/templates/` — the five files `MEMORY.md`, `configs.md`, `runbook.md`, `jobs.md`, `blockers.md`. The subagent resolves the worknote's directory and base name, creates `<dir>/<BaseName>.memory/`, and copies each template file in verbatim (substituting the project name into `MEMORY.md`'s heading).

## Subagent dispatch prompt skeleton

For any mutating action, dispatch a `general-purpose` Agent with a self-contained prompt. Fill the bracketed fields:

```
You are maintaining a shared research-memory store (machine-facing ground truth beside a human worknote).

Memory dir: <absolute path to <Name>.memory/>
Action: <init | link | add-job | update-config-status | add-learning>
Target file: <MEMORY.md | configs.md | runbook.md | jobs.md | blockers.md — the file this action writes>
Argument(s): <as provided>

File format (do not violate):
- MEMORY.md / configs.md / runbook.md are MUTABLE — rewrite in place; keep MEMORY.md ≤150 lines.
- jobs.md and blockers.md are APPEND-ONLY — append a new row/entry at EOF; never reorder or rewrite
  existing rows. The ONLY in-place edit allowed is filling a blocker's `Answer:` field.

Row/entry schema for this action (fill EVERY column; refuse if you cannot):
<paste the exact target schema, e.g.:
 jobs.md row: | timestamp | job id | purpose | config ref | owner | status | result ptr |
 configs.md row: | id/path | workdir | status | key knobs | evidence |  (status ∈ untested/working/failed/superseded)
 blockers.md entry: ### BLOCKED#<id> — <title> / timestamp / workdir / placeholder ref / Question / Evidence / Answer:
>
Evidence pointer is REQUIRED for add-job and update-config-status. No evidence → refuse and report why.

For `init`: create <dir>/<BaseName>.memory/ and copy the five template files from
  ${CLAUDE_PLUGIN_ROOT}/skills/research-memory/templates/ , substituting the project name into MEMORY.md's heading.
For `link`: create ./research-memory -> <memory dir> in the current workdir, then append the symlink
  name to .git/info/exclude (NOT .gitignore). Refuse if not inside a git worktree.

Timestamp: `date '+%Y-%m-%d %H:%M'`.

Return ≤3 lines: "<action> done — <one-line diff hint>". Do NOT echo file bodies.
```

## Refusals & edge cases

- `init` when the `.memory/` dir already exists → refuse; suggest `link` (to join it) or editing directly.
- `link` when the current directory is **not inside a git worktree** (no `.git`) → refuse; there is no `.git/info/exclude` to write.
- `link` when `./research-memory` already exists → refuse; report where it points.
- `add-job` or `update-config-status` **without an evidence pointer** → refuse; an unsupported fact does not belong in memory.
- `update-config-status` with a status outside `untested/working/failed/superseded`, or an illegal transition → refuse and name the legal transitions.
- Empty argument for any `add-*`/`update-*` action → refuse.
- `show-summary` / any action when the memory dir is missing → refuse; suggest `init`.

## Verification checklist

1. `init` created all five files and stamped the project name into `MEMORY.md`.
2. `link` created the symlink AND added it to `.git/info/exclude` (not `.gitignore`).
3. `add-job` appended exactly one row at EOF; prior rows byte-identical.
4. `update-config-status` changed only the target row and carried an evidence pointer.
5. `add-learning` landed under the correct runbook section; other sections unchanged.
