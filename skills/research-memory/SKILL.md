---
name: research-memory
description: "Lifecycle for a shared, machine-facing research memory that sits next to a human worknote — the ground-truth store (configs, runbook, job ledger, blockers) for all sub-project sessions. All writes are dispatched to subagents to keep the main context lean. TRIGGER when: user says research-memory init/link/add-job/update-config-status/add-learning/task-note/show-summary, /research-memory, \"research memory\", \"shared worknote memory\", or wants to record a job/config/learning/blocker beside a worknote."
author: Chunwei Yan
version: 0.3.0
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

- The symlink is registered in git's **info/exclude**, **never** `.gitignore`. Memory sharing is a local workflow concern, not a repo property — putting it in `.gitignore` would leak it into the tracked repo. Resolve the exclude file with `git rev-parse --git-path info/exclude` (works in both a normal repo and a linked worktree, where `.git` is a *file* and the exclude lives in the shared `$GIT_COMMON_DIR/info/exclude`), then append the symlink name to it.
- `link` is per-workdir: run it once in each tab/worktree that participates.

## Files & mutability

| File | Mutability | Contents |
|---|---|---|
| `MEMORY.md` | Mutable, rewritten in place, **≤150 lines** | Index + current ground truth: validated conclusions, pointers to reference/working configs, current focus. The only file main agents read routinely. |
| `configs.md` | Mutable table | Status of each config/recipe: id or path, owning workdir, status, key knobs, evidence pointer. |
| `runbook.md` | Mutable, sectioned | Execution learnings: Environment / Submit / Monitor / Collect / Pitfalls. |
| `jobs.md` | **Append-only ledger** | One row per job: timestamp, id, purpose, config ref, owner, status, result pointer. Status updates **append a new row** referencing the job id; never rewrite or reorder. |
| `blockers.md` | Append-only entries, mutable `Answer:` only | Open questions for the human: id, timestamp, workdir, placeholder ref, task file, Question, Evidence, `Answer:`. |
| `tasks/task-<id>.md` | Attempts append-only; Working notes mutable; Outcome write-once | Per-task restartable working state, one file per placeholder id. Created lazily on first claim. Read only by the owner/restarter of `#id`. |

## Memory hierarchy — detail lives low, curated facts flow up

Three explicit levels keep `MEMORY.md` small by construction: only promoted, evidence-backed facts rise; task detail stays reachable by pointer, never inlined.

| Level | Files | Reader | Content |
|---|---|---|---|
| **L1 global index** | `MEMORY.md` (≤150 lines) | every session, bounded read | validated conclusions, current focus, pointers |
| **L2 topic ledgers** | `configs.md` `runbook.md` `jobs.md` `blockers.md` | cross-task, structured | verdicts, recipes, job rows, Q&A |
| **L3 per-task** | `tasks/task-<id>.md` | only the owner/restarter of `#id` | restartable working state (Brief / Attempts / Working notes / Outcome) |

**Promotion protocol** (task → up, only via research-memory actions, each with an evidence pointer):

- config verdict proven → `update-config-status` (L2 `configs.md`).
- reusable execution learning/pitfall → `add-learning` (L2 `runbook.md`).
- job submitted / status change → `add-job` (L2 `jobs.md`).
- **validated conclusion the overall worknote depends on** → one bullet in `MEMORY.md` "Validated conclusions" (L1), with a pointer back to `tasks/task-<id>.md`.

Everything else stays in the task file. `MEMORY.md` stays ≤150 lines because it only ever receives promoted bullets. Completed task files are kept as a cheap archive — neatness is enforced at L1 by curation, not by deleting L3.

`configs.md` status state machine:

```
untested --> working    (job succeeded, verified)
untested --> failed      (job failed)
failed   --> untested    (config edited)
working  --> failed      (a validated config regresses)
working  --> superseded  (better config validated)
```

> A config marked `working` in `configs.md` is the signal that a recipe is safe to parallelize (Mode A in [[worknote-orchestrate]]). Memory quality directly buys parallelism.

## Context-saving contract (CRITICAL)

Inherited from the `verl-worknote` skill. The point is to keep the **main agent's context lean** while memory files grow:

- **All mutating actions** (`init`, `link`, `add-job`, `update-config-status`, `add-learning`, `task-note`, `add-blocker`, `answer-blocker`) MUST be dispatched to a subagent via the `Agent` tool. The main agent never loads the full file to mutate it.
- **Main agents do only bounded reads**: `MEMORY.md` (≤150 lines) directly via `Read`; anything larger goes through a read subagent that returns only the answer.
- **Mutable tables vs append-only ledgers**: `MEMORY.md`, `configs.md`, and `runbook.md` sections are rewritten in place; `jobs.md` and `blockers.md` entries are append-only (append new rows/entries; the only in-place edit permitted on an append-only file is filling a blocker's `Answer:` via `answer-blocker`); `tasks/task-<id>.md`: Attempts append-only, Working notes mutable, Outcome write-once.
- **Every fact carries a timestamp and an evidence pointer** (job id, log path, dashboard URL). A claim without evidence does not belong in memory — if the schema can't be filled, the fact isn't ready to record.
- **One topic per file** minimizes concurrent-write collisions across tabs. Strict entry/row schemas (facts and tables, not prose dumps) keep the rare cross-tab merge trivial.
- Subagents MUST return a **≤3-line** confirmation of the form `<action> done — <one-line diff hint>`. They MUST NOT echo file bodies (except `show-summary`, where the requested content IS the return, though `show-summary` is a direct read, not a dispatch).

## Actions

| Action | Dispatch | Effect |
|---|---|---|
| `init <worknote-path>` | Subagent | Create `<Worknote-Name>.memory/` beside the worknote and copy the five template files into it. |
| `link` | Subagent | Create `./research-memory` symlink in the current workdir + add it to git's `info/exclude` (resolved via `git rev-parse --git-path info/exclude`). |
| `task-note <id> <text>` | Subagent | Append `<text>` to `tasks/task-<id>.md` (Attempts or Working notes); create the file from `task.md` on first use. |
| `add-job <fields>` | Subagent | Append one row to `jobs.md`. |
| `update-config-status <id> <status>` | Subagent | Update the row for `<id>` in `configs.md` (evidence pointer required). |
| `add-learning <text>` | Subagent | Add `<text>` to `runbook.md` under the matching section. |
| `add-blocker <fields>` | Subagent | Append one entry to `blockers.md` (existing schema). |
| `answer-blocker <id> <text>` | Subagent | Fill the `Answer:` of entry `#id` — the one in-place edit permitted on `blockers.md`. |
| `show-summary` | Main (direct `Read`, limit ~150) | Bounded direct read of `MEMORY.md`. |

`init` copies templates from the plugin's `skills/research-memory/templates/` directory — the five files `MEMORY.md`, `configs.md`, `runbook.md`, `jobs.md`, `blockers.md`. `task.md` is **not** copied at init; per-task files are created lazily on first claim (see [[worknote-orchestrate]]). **The main agent resolves `${CLAUDE_PLUGIN_ROOT}` to an absolute path before filling the dispatch prompt** — a dispatched subagent does not inherit that variable, so the prompt must carry the concrete templates path. The subagent resolves the worknote's directory and base name, creates `<dir>/<BaseName>.memory/`, and copies each template file in verbatim (substituting the project name into `MEMORY.md`'s heading).

## Subagent dispatch prompt skeleton

For any mutating action, dispatch a `general-purpose` Agent with a self-contained prompt. Fill the bracketed fields:

```
You are maintaining a shared research-memory store (machine-facing ground truth beside a human worknote).

Memory dir: <absolute path to <Name>.memory/>
Action: <init | link | add-job | update-config-status | add-learning | task-note | add-blocker | answer-blocker>
Target file: <MEMORY.md | configs.md | runbook.md | jobs.md | blockers.md | tasks/task-<id>.md — the file this action writes>
Argument(s): <as provided>

File format (do not violate):
- MEMORY.md / configs.md / runbook.md are MUTABLE — rewrite in place; keep MEMORY.md ≤150 lines.
- jobs.md and blockers.md are APPEND-ONLY — append a new row/entry at EOF; never reorder or rewrite
  existing rows. The ONLY in-place edit allowed is filling a blocker's `Answer:` field.
- tasks/task-<id>.md — Attempts are APPEND-ONLY (never rewrite a prior `### Attempt N`); Working notes
  are mutable scratch; Outcome is filled once.

Row/entry schema for this action (fill EVERY column; refuse if you cannot):
<paste the exact target schema, e.g.:
 jobs.md row: | timestamp | job id | purpose | config ref | owner | status | result ptr |
 configs.md row: | id/path | workdir | status | key knobs | evidence |  (status ∈ untested/working/failed/superseded)
 blockers.md entry: ### BLOCKED#<id> — <title> / timestamp / workdir / placeholder ref / task file / Question / Evidence / Answer:
 tasks/task-<id>.md: Brief / Attempts (### Attempt N: tried, jobs, outcome, next step) / Working notes / Outcome
>
Evidence pointer is REQUIRED for add-job and update-config-status. No evidence → refuse and report why.

For `init`: create <dir>/<BaseName>.memory/ and copy the five template files from
  <ABSOLUTE templates path — the main agent expands ${CLAUDE_PLUGIN_ROOT} before dispatch> ,
  substituting the project name into MEMORY.md's heading. (task.md is NOT copied at init.)
For `link`: create ./research-memory -> <memory dir> in the current workdir, then append the symlink
  name to the file printed by `git rev-parse --git-path info/exclude` (NOT .gitignore). Create that
  file's parent directory if missing before appending (a fresh repo/worktree may lack `info/`). Refuse
  if `git rev-parse --git-dir` fails (not inside a git worktree).
For `task-note`: if tasks/task-<id>.md does not exist, create it from task.md (same absolute templates
  path) filling the Brief, then append <text> as a new Attempt section or Working-notes bullet.
For `add-blocker`: append ONE new `### BLOCKED#<id> — <title>` entry at EOF of blockers.md (never
  reorder or rewrite existing entries), filling every field of the entry schema including an evidence
  pointer. Leave `Answer:` empty. Refuse if evidence is missing.
For `answer-blocker`: fill ONLY the `Answer:` field of entry `#id` in blockers.md — the sole in-place
  edit permitted on this append-only file. Refuse if the answer text is empty, no entry `#id` exists,
  or that entry's `Answer:` is already non-empty.

Timestamp: `date '+%Y-%m-%d %H:%M'`.

Return ≤3 lines: "<action> done — <one-line diff hint>". Do NOT echo file bodies.
```

## Refusals & edge cases

- `init` when the `.memory/` dir already exists → refuse; suggest `link` (to join it) or editing directly.
- `link` when the current directory is **not inside a git worktree** (`git rev-parse --git-dir` fails) → refuse; there is no `info/exclude` to write.
- `link` when `./research-memory` already exists → refuse; report where it points.
- `add-job` or `update-config-status` **without an evidence pointer** → refuse; an unsupported fact does not belong in memory.
- `add-blocker` **without an evidence pointer** → refuse; a blocker must cite what motivates the question.
- `answer-blocker` with **empty answer text**, **no matching entry `#id`**, or an entry whose `Answer:` is **already filled** → refuse (the last preserves the append-only/write-once discipline).
- `update-config-status` with a status outside `untested/working/failed/superseded`, or an illegal transition → refuse and name the legal transitions.
- Empty argument for any `add-*`/`update-*` action → refuse.
- `show-summary` / any action when the memory dir is missing → refuse; suggest `init`.

## Verification checklist

1. `init` created all five files and stamped the project name into `MEMORY.md`.
2. `link` created the symlink AND added it to the file from `git rev-parse --git-path info/exclude` (not `.gitignore`); verify it resolves to a writable path even in a linked worktree.
3. `add-job` appended exactly one row at EOF; prior rows byte-identical.
4. `update-config-status` changed only the target row and carried an evidence pointer.
5. `add-learning` landed under the correct runbook section; other sections unchanged.
6. `task-note` created `tasks/task-<id>.md` from the template on first use and appended without rewriting a prior Attempt.
7. `add-blocker` appended exactly one entry at EOF with every field filled (evidence included) and an empty `Answer:`; prior entries byte-identical.
8. `answer-blocker` filled only the target entry's `Answer:` and refused if it was already answered.
