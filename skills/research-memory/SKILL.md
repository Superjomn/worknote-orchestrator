---
name: research-memory
description: "Lifecycle for a shared, machine-facing research memory that sits next to a human worknote — the ground-truth store (configs, runbook, job ledger, blockers) for all sub-project sessions. All writes are dispatched to subagents to keep the main context lean. TRIGGER when: user says research-memory init/link/add-job/update-config-status/add-learning/add-script/task-note/add-blocker/answer-blocker/promote-conclusion/set-focus/show-summary/query, /research-memory, \"research memory\", \"shared worknote memory\", \"refer to <worknote>.md worknote memory\", \"ask the memory / how to reproduce / where is <artifact>\", or wants to record OR look up a job/config/learning/blocker beside a worknote."
author: Chunwei Yan
version: 0.8.0
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
    tasks/                 # per-task L3 files, created lazily
    scripts/               # OPTIONAL: reusable collection/analysis helpers
```

The memory dir holds **only** the five files + `tasks/` + an optional `scripts/` directory. `scripts/` is the one sanctioned home for reusable collection/analysis helper artifacts (parsers, tps extractors, plotting); every script MUST be referenced from `runbook.md` §Collect so it is discoverable. Nothing else lives at the memory root — a stray helper at the root is a defect, move it into `scripts/` and cite it from the runbook.

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
| `jobs.md` | **Append-only ledger** | One row per job: timestamp, id, purpose, config ref, owner, status, result pointer. Status updates **append a new row** referencing the job id; never rewrite or reorder. A terminal status change (`finished`/`failed`/`cancelled`) appends **its own row for that job id** — never fold job X's terminal state into job Y's row (each job id's lifecycle is a self-contained chain of rows). |
| `blockers.md` | Append-only entries, mutable `Answer:` only | Open questions for the human: id, timestamp, workdir, placeholder ref, task file, Question, Evidence, `Answer:`. |
| `tasks/task-<id>.md` | Attempts append-only; Working notes mutable; Outcome write-once | Per-task restartable working state, one file per placeholder id. Created lazily on first claim. Read only by the owner/restarter of `#id`. |
| `scripts/` (optional) | Mutable helper files | Reusable collection/analysis helpers (parsers, extractors). Only sanctioned non-file-list artifact at the memory root; every script MUST be referenced from `runbook.md` §Collect. |

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
- **validated conclusion the overall worknote depends on** → `promote-conclusion` (L1): one bullet in `MEMORY.md` "Validated conclusions", with a pointer back to `tasks/task-<id>.md`.
- **current-focus shift** → `set-focus` (L1): rewrite the `MEMORY.md` "Current focus" bullets (forward-looking: in-progress + immediate next steps, **not** a completion log).

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

**`working` verdict semantics (CRITICAL).** A `working` verdict requires the cited evidence job to have reached a **successful terminal state for the config's actual purpose** — not merely that some sub-effect was observed. A run that crashed or failed is `failed`, even if a sub-effect was verified along the way (e.g. "the reuse path engaged" observed before an OOM). Record that verified sub-effect in the config's key-knobs or the evidence pointer, **not** in the status: a crashed job never yields `working`. Concretely, a `working` verdict requires the cited evidence job's **latest `jobs.md` row** to be `finished` (the verified-success terminal); if that row is `failed`, `cancelled`, still `submitted`/`running`, or absent/unresolvable, the transition is illegitimate → refuse, naming the actual state.

## Context-saving contract (CRITICAL)

Inherited from the `verl-worknote` skill. The point is to keep the **main agent's context lean** while memory files grow:

- **All mutating actions** (`init`, `link`, `add-job`, `update-config-status`, `add-learning`, `add-script`, `task-note`, `add-blocker`, `answer-blocker`, `promote-conclusion`, `set-focus`) MUST be dispatched to a subagent via the `Agent` tool. The main agent never loads the full file to mutate it. (`query` is **read-only** — it mutates nothing, so it is exempt from this mutating-dispatch list, but it is still dispatched to keep the L2/L3 file bodies out of the main context.)
- **Main agents do only bounded reads**: `MEMORY.md` (≤150 lines) directly via `Read`; anything larger goes through the **`query` action** — a read subagent that returns only the answer + evidence pointers, never a file body. Reaching past `MEMORY.md` into the L2 ledgers / L3 task files / worknote markdown is the `query` dispatch's job, precisely so the main agent's context stays lean.
- **Mutable tables vs append-only ledgers**: `MEMORY.md`, `configs.md`, and `runbook.md` sections are rewritten in place; `jobs.md` and `blockers.md` entries are append-only (append new rows/entries; the only in-place edit permitted on an append-only file is filling a blocker's `Answer:` via `answer-blocker`); `tasks/task-<id>.md`: Attempts append-only, Working notes mutable, Outcome write-once.
- **Every fact carries a timestamp and an evidence pointer** (job id, log path, dashboard URL). A claim without evidence does not belong in memory — if the schema can't be filled, the fact isn't ready to record.
- **One topic per file** minimizes concurrent-write collisions across tabs. Strict entry/row schemas (facts and tables, not prose dumps) keep the rare cross-tab merge trivial.
- Subagents MUST return a **≤3-line** confirmation of the form `<action> done — <one-line diff hint>`. They MUST NOT echo file bodies. Two read exceptions return *content* rather than a diff hint: `show-summary` (a direct `Read`, not a dispatch) and `query` (a read-only dispatch whose return IS the ≤10-line answer + evidence pointers — never a raw file body).

## Actions

| Action | Dispatch | Effect |
|---|---|---|
| `init <worknote-path>` | Subagent | Create `<Worknote-Name>.memory/` beside the worknote and copy the five template files into it. |
| `link` | Subagent | Create `./research-memory` symlink in the current workdir + add it to git's `info/exclude` (resolved via `git rev-parse --git-path info/exclude`). |
| `task-note <id> <text>` | Subagent | Append `<text>` to `tasks/task-<id>.md` (Attempts or Working notes); create the file from `task.md` on first use. |
| `add-job <fields>` | Subagent | Append one row to `jobs.md` (status ∈ submitted/running/finished/failed/cancelled; a terminal status appends its own row per job id; an unregistered `config ref` auto-adds an `untested` `configs.md` row in the same dispatch). |
| `update-config-status <id> <status>` | Subagent | Update the row for `<id>` in `configs.md` (evidence pointer required; a `working` verdict requires the cited evidence job's latest `jobs.md` row to be `finished`). "Reference configs" is a **curated best-per-family shortlist**, NOT a mirror of every `working` row (the full set lives in `configs.md`): a `working` transition mirrors into MEMORY.md only when `<id>` becomes the **current best of its family/purpose** — then add/replace `<id> → configs.md#... (status: ...)` and supersede the prior family-best pointer; an ordinary `working` transition that isn't a new family-best updates `configs.md` only. When the OLD status was `working`/`superseded` AND `<id>` already has a Reference line, update that line in place to the new status (the default; drop it only when a successor's mirror line replaces it (supersede chain) or the human asked for its removal). |
| `add-learning <text>` | Subagent | Add `<text>` to `runbook.md` under the matching section. |
| `add-script <name> <description>` | Subagent | Place/move a reusable helper under `scripts/<name>` **and** add its `runbook.md` §Collect citation in the SAME dispatch. Refuse if the script is left at the memory root or goes uncited. |
| `add-blocker <fields>` | Subagent | Append one entry to `blockers.md` (existing schema). |
| `answer-blocker <id> <text>` | Subagent | Fill the `Answer:` of the **latest (last)** entry for `#id` — the one in-place edit permitted on `blockers.md`. |
| `promote-conclusion <id> <text>` | Subagent | Append ONE bullet under `MEMORY.md` "Validated conclusions", ending with an evidence pointer + timestamp + `→ tasks/task-<id>.md` (updates in place if a bullet for that task file already exists). Requires an existing `tasks/task-<id>.md`. Keep `MEMORY.md` ≤150 lines (curate/compress oldest bullets if needed, never drop pointers). |
| `set-focus <text>` | Subagent | Rewrite `MEMORY.md` "Current focus" section in place as a **forward-looking** list (in-progress + immediate next steps), **≤5 bullets**, NOT a completion log. Completed placeholders are recorded in Validated conclusions (if promoted), `jobs.md`, and the task Outcome — **not** as a `DONE #N` bullet here. If the rewrite would exceed 5 bullets, the subagent MUST prune completed/superseded bullets in the SAME edit. |
| `show-summary` | Main (direct `Read`, limit ~150) | Bounded direct read of `MEMORY.md`. |
| `query [<worknote>] <question>` | Subagent (**read-only**) | Answer a question from the store without loading its bodies into the main context. `query <question>` targets the local `./research-memory/`. `query <worknote-path> <question>` is a **foreign reference**: deduce `<dir>/<Base>.memory/` beside the named worknote markdown (same directory, relative path fine); search it first, and if that memory dir is missing OR lacks the answer, fall back to a bounded grep of the worknote markdown itself. **Search order** (read in order; stop once the answer is fully assembled): `MEMORY.md` → the matching L2 ledger (`jobs.md`/`configs.md`/`runbook.md`/`blockers.md`) → `tasks/task-*.md` → `scripts/` → worknote-markdown fallback. **Answer ≤10 lines, every claim carrying an evidence pointer** (file + row/anchor/section/line); if not derivable, return an explicit `NOT FOUND in <what was searched>` — never guess. The dispatch **mutates nothing**: the store must be byte-identical after a query. |

`init` copies templates from the plugin's `skills/research-memory/templates/` directory — the five files `MEMORY.md`, `configs.md`, `runbook.md`, `jobs.md`, `blockers.md`. `task.md` is **not** copied at init; per-task files are created lazily on first claim (see [[worknote-orchestrate]]). **The main agent resolves `${CLAUDE_PLUGIN_ROOT}` to an absolute path before filling the dispatch prompt** — a dispatched subagent does not inherit that variable, so the prompt must carry the concrete templates path. The subagent resolves the worknote's directory and base name, creates `<dir>/<BaseName>.memory/`, and copies each template file in verbatim (substituting the project name into `MEMORY.md`'s heading).

## Subagent dispatch prompt skeleton

For any mutating action, dispatch a `general-purpose` Agent with a self-contained prompt. Fill the bracketed fields:

```
You are maintaining a shared research-memory store (machine-facing ground truth beside a human worknote).

Memory dir: <absolute path to <Name>.memory/>
Action: <init | link | add-job | update-config-status | add-learning | add-script | task-note | add-blocker | answer-blocker | promote-conclusion | set-focus>
Target file: <MEMORY.md | configs.md | runbook.md | jobs.md | blockers.md | scripts/<name> | tasks/task-<id>.md — the file this action writes (update-config-status ALSO touches MEMORY.md when the old OR new status is working/superseded; add-job ALSO touches configs.md when its config ref is unregistered; add-script writes scripts/<name> AND cites it in runbook.md §Collect; promote-conclusion and set-focus write MEMORY.md)>
Argument(s): <as provided>

File format (do not violate):
- MEMORY.md / configs.md / runbook.md are MUTABLE — rewrite in place; keep MEMORY.md ≤150 lines.
- jobs.md and blockers.md are APPEND-ONLY — append a new row/entry at EOF; never reorder or rewrite
  existing rows. The ONLY in-place edit allowed is filling a blocker's `Answer:` field.
- tasks/task-<id>.md — Attempts are APPEND-ONLY (never rewrite a prior `### Attempt N`); Working notes
  are mutable scratch; Outcome is filled once.

Template-hygiene rule (all actions): when writing the FIRST real row/bullet/entry into a section or
table that still contains an italic `_( … )_` template example, delete that example line as part of
the SAME edit. Never leave a template example beside real data.

Row/entry schema for this action (fill EVERY column; refuse if you cannot):
<paste the exact target schema, e.g.:
 jobs.md row: | timestamp | job id | purpose | config ref | owner | status | result ptr |  (status ∈ submitted/running/finished/failed/cancelled)
 configs.md row: | id/path | workdir | status | key knobs | evidence |  (status ∈ untested/working/failed/superseded)
 blockers.md entry: ### BLOCKED#<id> — <title> / timestamp / workdir / placeholder ref / task file / Question / Evidence / Answer:
 tasks/task-<id>.md: Brief (task, workdir, worknote, context, blockers) / Attempts (### Attempt N: context, tried, jobs, outcome, next step) / Working notes / Outcome
>
Evidence pointer is REQUIRED for add-job, update-config-status, and add-blocker. No evidence → refuse and report why.

For `init`: create <dir>/<BaseName>.memory/ and copy the five template files from
  <ABSOLUTE templates path — the main agent expands ${CLAUDE_PLUGIN_ROOT} before dispatch> ,
  substituting the project name into MEMORY.md's heading. (task.md is NOT copied at init.)
For `link`: create ./research-memory -> <memory dir> in the current workdir, then append the symlink
  name to the file printed by `git rev-parse --git-path info/exclude` (NOT .gitignore). Create that
  file's parent directory if missing before appending (a fresh repo/worktree may lack `info/`). Refuse
  if `git rev-parse --git-dir` fails (not inside a git worktree).
For `task-note`: if tasks/task-<id>.md does not exist, create it from task.md (same absolute templates
  path) filling the Brief, then append <text> as a new Attempt section or Working-notes bullet.
For `add-job`: append ONE row at EOF of jobs.md. The `status` MUST be one of
  submitted/running/finished/failed/cancelled — refuse and name the invented value otherwise
  (`unknown` is a resolution result, never a stored status). A scancelled/released pool reservation
  is recorded as **`cancelled`**, with the release reason in the result ptr; `released` is not a
  status. A terminal status change
  (finished/failed/cancelled) appends its OWN row for that job id — never fold this job's terminal
  state into another job's row. If the `config ref` names a config that has NO row in configs.md,
  add an `untested` configs.md row for it in this SAME dispatch (evidence: the job being recorded)
  so every `config ref` resolves to a real configs.md entry. Normalize the ref to its anchor when
  minting that row: a ref `configs.md#pmt32` yields a configs.md row whose id is `pmt32`, and the
  row's evidence cites the job id being recorded (e.g. `srun-800`).
For `add-learning`: pick the runbook.md section the fact belongs to and add it there — Environment
  (setup prerequisites / env vars / images), Submit (launch commands), Monitor (job-id → status
  resolution), Collect (result extraction / parse steps / helper scripts), Pitfalls (a gotcha + its
  fix, ONLY). Do NOT bury an environment/submit/monitor/collect fact inside a Pitfalls entry. If the
  learning spans multiple topics, SPLIT it into one entry per matching section rather than dumping it
  all into one.
For `add-script`: place (or move) the helper at scripts/<name> under the memory dir — creating
  scripts/ if absent — AND add a §Collect citation for it in runbook.md, both in this SAME dispatch.
  A reusable helper is never left at the memory root and never uncited: refuse if <name> would sit
  at the root (not under scripts/) or if you cannot add its runbook §Collect citation. The two-part
  write (placement + citation) is atomic — do not do one without the other.
For `add-blocker`: append ONE new `### BLOCKED#<id> — <title>` entry at EOF of blockers.md (never
  reorder or rewrite existing entries), filling every field of the entry schema including an evidence
  pointer. Leave `Answer:` empty. Refuse if evidence is missing.
For `answer-blocker`: fill ONLY the `Answer:` field of the LATEST (last) entry for `#id` in
  blockers.md — a re-blocked task appends a second `### BLOCKED#<id>` entry, so target the most
  recent one. This is the sole in-place edit permitted on this append-only file. Refuse if the answer
  text is empty, no entry `#id` exists, or ALL entries for `#id` already have a non-empty `Answer:`.
For `update-config-status`: a `working` verdict requires the cited evidence job's LATEST jobs.md row
  to be `finished` — REFUSE unless it is; `failed`, `cancelled`, still-`submitted`/`running`, or
  absent/unresolvable all refuse, naming the actual state (a crashed run stays `failed` even if a
  sub-effect was verified; record the sub-effect in key-knobs/evidence, not in status). After editing
  the `<id>` row in configs.md, decide the MEMORY.md "Reference configs" mirror. Reference configs is
  a CURATED best-per-family shortlist, NOT a mirror of every `working` row (the full set lives in
  configs.md), so:
  - NEW status `working`/`superseded`: mirror ONLY when `<id>` is the current BEST config of its
    family/purpose. If so, add or replace the line for `<id>` as
    `<id> → configs.md#<anchor> (status: <status>)` AND supersede the prior family-best pointer (its
    line steps down / is replaced). An ordinary `working` transition that is NOT a new family-best
    touches configs.md ONLY — do not add a Reference line (that would turn the shortlist into a mirror
    of every working row).
  - OLD status `working`/`superseded` AND `<id>` already has a Reference line: update that existing
    line IN PLACE to the new status by default, e.g. a `working → failed` regression rewrites
    `(status: working)` to `(status: failed)`; drop the line entirely ONLY when a successor's mirror
    line replaces it (supersede chain) or the human explicitly asked for its removal.
  Touch MEMORY.md only in those cases (e.g. an `untested → failed` transition, or a non-best `working`
  transition, mirrors nothing).
For `promote-conclusion`: append ONE bullet under MEMORY.md "Validated conclusions". The text MUST
  carry an evidence pointer (job id, log path, dashboard URL); the bullet MUST end with the timestamp
  and `→ tasks/task-<id>.md`. REFUSE if the text has no evidence pointer, or if tasks/task-<id>.md
  does not exist (a conclusion must trace back to a real task file). If a Validated-conclusions bullet
  already points at `tasks/task-<id>.md`, UPDATE that bullet in place rather than appending a second.
  Keep MEMORY.md ≤150 lines — if near the limit, compress/curate the OLDEST bullets, never drop their
  pointers.
For `set-focus`: rewrite ONLY the "Current focus" section of MEMORY.md in place as a
  FORWARD-LOOKING list — in-progress placeholders + immediate next steps, ≤5 bullets; touch no
  other section. Current focus is NOT a changelog: never append a per-placeholder `DONE #N …`
  bullet — a completed placeholder is recorded in Validated conclusions (if promoted), jobs.md, and
  the task Outcome, and is DROPPED from Current focus. If the supplied rewrite would leave >5
  bullets, PRUNE completed/superseded bullets in this SAME edit to get to ≤5. Refuse if the text is
  empty, or if it asks to append a pure `DONE #N` changelog bullet.

Timestamp: `date '+%Y-%m-%d %H:%M'`.

Return ≤3 lines: "<action> done — <one-line diff hint>". Do NOT echo file bodies.
```

## Query dispatch skeleton (read-only)

`query` is the one dispatch whose **return IS the content** — the answer itself, not a diff hint (like `show-summary`, but reaching past `MEMORY.md`). It is **read-only**: it mutates nothing. Dispatch a `general-purpose` Agent with a self-contained prompt. Fill the bracketed fields:

```
You are answering a question from a shared research-memory store (machine-facing ground truth
beside a human worknote). You are READ-ONLY: you MUST NOT create, modify, or delete any file.
The store must be byte-identical after you finish.

Memory dir: <one of:
  - LOCAL: <absolute path to ./research-memory/>
  - FOREIGN: worknote markdown path = <absolute path to <Base>.md>. DEDUCE the memory dir as
    <same-dir>/<Base>.memory/  (e.g. /p/Prod.md -> /p/Prod.memory/). If that dir EXISTS, search it;
    if it is MISSING or lacks the answer, fall back to a bounded grep of the worknote markdown itself.>
Question: <the natural-language question>

Search order — read in this order and STOP once you have a FULLY authoritative answer. A single hit is authoritative only when it answers the WHOLE question; a multi-part question (e.g. the recipes below) assembles across several sources before it is complete:
1. MEMORY.md            (validated conclusions, current focus, reference-config pointers)
2. the matching L2 ledger — pick by topic:
     jobs.md      for job rows / result pointers / reproduction
     configs.md   for config status / key knobs
     runbook.md   for how-to (Environment/Submit/Monitor/Collect/Pitfalls)
     blockers.md  for open questions / answers
3. tasks/task-*.md      (per-task Attempts / Working notes / Outcome)
4. scripts/             (helper names/paths cited from runbook §Collect)
5. worknote-markdown fallback (FOREIGN only, when the memory dir is missing or has no answer):
     bounded grep of <Base>.md; cite the section heading or line number.

Answer format (STRICT):
- ≤10 lines total.
- EVERY claim carries an evidence pointer: file + row/anchor/§section/line
  (e.g. `jobs.md row srun-950`, `runbook.md §Submit`, `configs.md#pmt-repro`, `Prod.memory/MEMORY.md`,
   `Notes.md §Deploy` / `Notes.md:42`).
- If the answer is NOT derivable from what you searched, return exactly:
  `NOT FOUND in <what was searched>` — never guess, never invent a specific value.

Worked recipes (assemble from pointers, do not invent):
- "how to reproduce the last job":
    latest jobs.md row (the LAST row = most recent job id) → its `config ref` row in configs.md
    (key knobs) → runbook.md §Submit (the launch command) → assemble a reproduction recipe naming
    THAT job id, its config, and the submit command. Cite each source.
- "list all the nsys reports":
    scan jobs.md result pointers + tasks/task-*.md Attempts + runbook.md §Collect for `nsys` /
    `.nsys-rep` paths; list every distinct path, each with the file it came from. Do not list
    non-nsys pointers.

Read-only rule (REPEAT): you MUST NOT write anything. Do not "fix" stale data you notice — only report.
Return: the answer itself (≤10 lines with evidence pointers, or the NOT FOUND line). No file bodies.
```

## Refusals & edge cases

- `init` when the `.memory/` dir already exists → refuse; suggest `link` (to join it) or editing directly.
- `link` when the current directory is **not inside a git worktree** (`git rev-parse --git-dir` fails) → refuse; there is no `info/exclude` to write.
- `link` when `./research-memory` already exists → refuse; report where it points.
- `add-job` or `update-config-status` **without an evidence pointer** → refuse; an unsupported fact does not belong in memory.
- `add-job` with a **status outside `submitted/running/finished/failed/cancelled`** → refuse and name the invented value (e.g. `released`); the ledger vocabulary is closed (`unknown` is a resolution result, never a stored status). A scancelled/released pool reservation maps to **`cancelled`** (release reason in the result ptr), not `released`.
- `update-config-status <id> working` whose **cited evidence job's latest `jobs.md` row is not `finished`** → refuse, naming the actual state; a `working` verdict needs a `finished` terminal, so `failed`, `cancelled`, still-`submitted`/`running`, or absent/unresolvable all refuse (a crashed run stays `failed` even if a sub-effect was verified — record the sub-effect in key-knobs/evidence).
- `add-blocker` **without an evidence pointer** → refuse; a blocker must cite what motivates the question.
- `answer-blocker` with **empty answer text**, **no matching entry `#id`**, or where **all** entries for `#id` are **already filled** → refuse (the last preserves the append-only/write-once discipline). When a placeholder was re-blocked, `answer-blocker` fills the **latest** `#id` entry.
- `update-config-status` with a status outside `untested/working/failed/superseded`, or an illegal transition → refuse and name the legal transitions.
- `promote-conclusion` **without an evidence pointer**, or when **`tasks/task-<id>.md` is missing** → refuse; a promoted conclusion must trace back to a real task file and cite its evidence.
- `promote-conclusion` when a Validated-conclusions bullet **already points at `tasks/task-<id>.md`** → do NOT append a duplicate; update that bullet in place.
- `set-focus` with **empty text** → refuse.
- `set-focus` asked to append a pure `DONE #N` changelog bullet, or a rewrite that would leave **>5
  bullets** without pruning completed/superseded ones → refuse (or prune to ≤5 in the same edit);
  Current focus is forward-looking, not a completion log.
- `add-script` that would leave the helper **at the memory root** (not under `scripts/`) or **uncited** in `runbook.md` §Collect → refuse; a reusable helper must be placed under `scripts/` and cited in the same dispatch.
- Empty argument for any `add-*`/`update-*` action → refuse.
- `show-summary` / any action when the memory dir is missing → refuse; suggest `init`.
- `query` with an **empty question** → refuse; there is nothing to answer.
- `query <worknote-path> <question>` where the **worknote markdown file does not exist** → refuse, naming the path; the `<Base>.memory/` deduction has no anchor to hang off.
- `query` whose answer is **not present** in the searched store/worknote → this is a **miss, not an invention** (and not a hard refusal either): return the explicit `NOT FOUND in <what was searched>` line, never fabricate a plausible value to satisfy the question.
- Any **file mutation during a `query`** → forbidden; `query` is strictly read-only, and the store must be byte-identical afterward (a query that needs to "fix" something is out of scope — report it, don't write it).

## Verification checklist

1. `init` created all five files and stamped the project name into `MEMORY.md`.
2. `link` created the symlink AND added it to the file from `git rev-parse --git-path info/exclude` (not `.gitignore`); verify it resolves to a writable path even in a linked worktree.
3. `add-job` appended exactly one row at EOF (prior rows byte-identical) with a status in `submitted/running/finished/failed/cancelled`; a terminal status landed as its own row for that job id (never folded into another job's row).
4. `update-config-status` changed only the target row and carried an evidence pointer; a `working` verdict's cited job's latest `jobs.md` row is `finished` (not `failed`/`cancelled`/`submitted`/`running`/unresolvable).
5. `add-learning` landed under the correct runbook section; other sections unchanged.
6. `task-note` created `tasks/task-<id>.md` from the template on first use and appended without rewriting a prior Attempt.
7. `add-blocker` appended exactly one entry at EOF with every field filled (evidence included) and an empty `Answer:`; prior entries byte-identical.
8. `answer-blocker` filled only the **latest** `#id` entry's `Answer:` and refused only if **all** entries for `#id` were already answered.
9. `promote-conclusion` appended exactly one bullet ending with an evidence pointer + timestamp + `→ tasks/task-<id>.md`, removed any template example bullet in that section, and updated in place (not duplicated) when a bullet for that task file already existed.
10. `set-focus` rewrote only the "Current focus" section (every other section byte-identical) as a
    forward-looking list of ≤5 bullets, with no `DONE #N` changelog entries.
11. `update-config-status` treated "Reference configs" as a curated best-per-family shortlist: a NEW `working`/`superseded` status added/replaced the `<id>` line ONLY when `<id>` was the new family-best (superseding the prior family-best pointer) and left MEMORY.md untouched for a non-best `working` transition; when the OLD status was `working`/`superseded` and `<id>` had a Reference line it updated that line IN PLACE to the new status by default (dropping it only on a supersede chain or explicit human removal) — e.g. a `working → failed` regression leaves no stale `(status: working)` line; MEMORY.md was untouched when neither applied (e.g. `untested → failed`).
12. `add-job` whose `config ref` named an unregistered config auto-added an `untested` `configs.md` row for it in the same dispatch (every `config ref` resolves to a `configs.md` entry).
13. `add-script` placed the helper under `scripts/<name>` (never at the memory root) AND added its `runbook.md` §Collect citation in the same dispatch — both or neither.
14. `query` returned an **evidence-pointed answer** (≤10 lines, every claim citing a file + row/anchor/§section/line) **or an explicit `NOT FOUND in <searched>`** when the fact was absent (a miss, never an invented value), and the store is **byte-identical** after the query (read-only). A foreign-worknote `query <worknote>.md <question>` deduced `<Base>.memory/` beside the worknote correctly, searched it first, and **fell back to a bounded grep of the worknote markdown** when the memory dir was missing or lacked the answer (citing the markdown §section/line).
