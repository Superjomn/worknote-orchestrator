---
name: worknote-orchestrate
description: "Fill <<...>> placeholders in a human worknote by classifying each as fill-from-data or needs-work, then running the needs-work ones as jobs across parallel coordinator-driven agents (Mode A) or a human-driven tab (Mode B), with a claiming protocol, worknote-embedded state markers, and ONE batched human-feedback round. Layers on complete-report and records everything via research-memory. TRIGGER when: user runs /worknote-orchestrate, says \"fill worknote placeholders\", \"run worknote jobs\", \"orchestrate the worknote\", or wants to execute + fill placeholders that require running jobs."
author: Chunwei Yan
version: 0.4.0
user_invocable: true
---

# worknote-orchestrate — Run + Fill Worknote Placeholders

Orchestrate a human worknote whose `<<...>>` placeholders may require **running jobs**, not just generating text. It layers execution semantics on top of `complete-report` and uses [[research-memory]] as the shared ground truth and cross-session channel.

> **Design principle — the worknote is human-owned and mutable at all times.** The human may add, reword, move, or delete placeholders *while agents are running*. Agents must tolerate this: **memory is ground truth for results; the worknote write is best-effort.** Never lose a result because the worknote changed under you (see "Results are never lost").

## Relationship to `complete-report`

This skill **reuses** `complete-report`'s mechanics and **extends** them with execution:

- **Scan → plan-mode approval → top-to-bottom `Edit` replacement → re-scan.** Same loop.
- **Placeholder grammar** (restated here so this skill is self-sufficient even when `complete-report` isn't installed):
  - Regex: `<<[^<>]+?>>` — `<<`, then one or more non-`<`/`>` chars (non-greedy), then `>>`.
  - Apply with multiline/DOTALL semantics (`Grep multiline: true`; Python `re.DOTALL`; ripgrep `-U --multiline-dotall`) so a placeholder body may span newlines.
  - Non-greedy `+?` pairs each `<<` with its *closest* `>>`; the `[^<>]` class forbids nested `<`/`>`.
  - Core replace step: read a narrow window (`start_line-20` .. `end_line+20`), `Edit` with `old_string` = the **full multi-line placeholder** exactly as written, work top-to-bottom to avoid line drift, then re-scan.
- **Soft dependency**: for the richer **content-structure rules** (tables over prose, bold-term bullets, brevity), and the **figure/math gating** rules, cite and defer to `complete-report`. If it is installed, follow its Content Structure / Figures / Math sections verbatim for generated content. This skill does not duplicate that ruleset.

## Output discipline

- **Only conclusions go into the worknote.** Command lines, intermediate numbers, evidence, and job details go to shared memory (`jobs.md`, `runbook.md`, `configs.md`); worknote content may cite them by pointer.
- Replacement style matches the surrounding human text (voice, heading depth, table conventions) per `complete-report`.

## Arguments & invocation modes

- **Whole file**: `/worknote-orchestrate <worknote>` — scan all placeholders, classify, present the plan (plan mode), execute all approved items, in parallel where independent. Runs as the **coordinator** (Mode A).
- **Single placeholder**: `/worknote-orchestrate <worknote> #<id>` — treat one placeholder as this session's task; work it, replace it with the final result on completion. This is **Mode B** (human-driven tab).
- **Status**: `/worknote-orchestrate <worknote> status` — read-only dashboard reconciliation. No writes, no dispatches. See "status invocation".

## Classification (at plan time)

Classify every placeholder during the plan phase:

| Class | Meaning | Execution |
|---|---|---|
| **fill-from-data** | Answerable from shared memory, the job ledger, or existing artifacts. | Direct generation in the orchestrating session (standard `complete-report`). |
| **needs-work** | Requires running jobs or analysis in a specific workdir. | Dispatched to a placeholder-agent (Mode A) or claimed by a tab (Mode B). |

## Hint directives

Placeholders may embed optional directives. These are **hints, not a DSL** — interpret best-effort, confirm in plan mode:

| Directive | Hint |
|---|---|
| `<<@dir:<workdir> ...>>` | Work must run in the named working directory. |
| `<<@memory ...>>` | Answer from shared memory only; do not run jobs → fill-from-data. |
| `<<@run ...>>` | Expect job submission → classify as needs-work. |

## Placeholder ids — stamped at plan approval

Every marker and Mode B invocation uses a stable `#<id>`, so ids must be defined, not derived from scan order (scan-order ordinals shift the moment the human inserts a placeholder above an existing one).

- **Stamp at plan approval.** When the coordinator finalizes the plan, it rewrites each still-pending placeholder to embed an id: `<<... body ...>>` → `<<#7 ... body ...>>`. This stays a valid `<<[^<>]+?>>` placeholder (no nested `<`/`>`).
- **Monotonic, never reused.** The next id is `max(existing ids) + 1`, where the max is taken over **three sources** so ids never collide even after every marker completes and disappears from the worknote:
  1. **Marker ids in the worknote** — a `#N` that immediately follows `<<`, `<<RUNNING`, or `<<BLOCKED` (i.e. the placeholder's *own* id). A `#N` inside a placeholder *body* (e.g. `<<#7 see issue #123>>`) is a prose ref and must **not** inflate the counter — only the id at the head of the placeholder counts.
  2. **Archived task files** — the `<id>` in every `research-memory/tasks/task-<id>.md` filename.
  3. **Blocker entries** — every `BLOCKED#<id>` in `blockers.md`.

  Deleting a placeholder never frees its id: once all markers complete, sources 2 and 3 still pin the max, so a later scan will not reuse an id that already owns a `task-<id>.md` file or a blocker entry.
- **Human-added placeholders get stamped at the next scan.** A fresh `<<...>>` with no `#id` is assigned the next id on the following scan (the next planning scan — `status` never stamps). The only other stamp site is a **Mode B claim on an un-stamped target**, which stamps exactly one placeholder (see Mode B "Stamp-on-claim").
- Because ids are stable, **a stamped `#id` resolves to exactly one placeholder** (or its `RUNNING`/`BLOCKED` marker), unambiguously. This uniqueness holds **once stamped**; a Mode B `#id` target on a never-planned worknote may match no stamped placeholder yet — it goes through the Mode B pick-and-stamp path (see "Stamp-on-claim").

## State machine & markers — the worknote is the dashboard

Placeholder state is written into the worknote itself, so a human opening the file sees live status with no extra tooling:

```
pending:     <<...>>                                        (unclaimed)
running:     <<RUNNING#id owner=... job=... since=... task: ...>>
blocked:     <<BLOCKED#id owner=... since=... task: ... Q: {question}>>
blocked+ans: <<BLOCKED#id ... Q: {question} A: {answer}>>
done:        final content (placeholder gone)
```

Transitions:

```
pending  --> pending    (stamped at plan approval — status never stamps: <<...>> becomes <<#id ...>>)
pending  --> running   (claimed: agent dispatch or tab invocation)
running  --> done       (success — placeholder replaced with final content)
running  --> blocked    (failure needing human input)
blocked  --> blocked+ans (human writes answer inline or in blockers.md)
blocked+ans --> running  (re-activated with the answer in a fresh agent's prompt — marker rewritten job=pending, same claim rule as pending-->running)
blocked  --> running    (human takeover — Mode B in that workdir)
running  --> running    (re-invocation resumes via the jobs.md ledger)
running  --> cancelled  (human deleted the marker — see "Human edits mid-flight")
running  --> running    (superseded: human edited task:, re-dispatched with new text)
```

> **Markers stay valid `<<...>>` placeholders** — no nested `<` or `>` inside them — so `complete-report` (and this skill's own scan) still find them. Example markers:
>
> ```
> <<RUNNING#3 owner=tab:duckling-pie job=srun-8812345 since=2026-07-09 task: sweep dp=4>>
> <<BLOCKED#3 owner=agent since=2026-07-09 task: sweep dp=4 Q: OOM at dp=4 — reduce batch or skip? A: skip, note in report>>
> ```

## Mode A — coordinator-driven parallel agents (autonomous tasks)

One coordinator session runs the whole-file invocation:

1. Scan + classify + plan-mode approval (per Classification and Risk-based selection below). On plan approval, call research-memory `set-focus` with the active `#id`s + one-line intents so MEMORY.md "Current focus" reflects this round.
2. Dispatch each approved needs-work placeholder to a **placeholder-agent** — a subagent instructed to `cd` into the target workdir first. Independent placeholders are dispatched **in parallel** (one message, multiple `Agent` calls). Before dispatching, flip the placeholder to `<<RUNNING#id owner=agent job=pending since=... task: ...>>` — the job id does not exist until the agent submits, so the coordinator writes `job=pending` and the agent fills the real id once it has one (skeleton step 3).
3. Placeholder-agents **never block on human input.** On a blocker they: write a structured `blockers.md` entry via research-memory `add-blocker`, flip the placeholder to `<<BLOCKED#id ...>>`, and return a status line.
4. The coordinator collects completions and **serializes ALL pending blockers into a single `AskUserQuestion` round** — one interrupt instead of N scattered ones. In this same completion/blocker round it refreshes MEMORY.md "Current focus" via `set-focus` (drop finished `#id`s, keep the still-open/blocked ones).
5. Each answer is written into its blocker's `Answer:` field via research-memory `answer-blocker <id> <text>` (and inline into the marker), and the affected placeholders are immediately re-dispatched (`BLOCKED` → `RUNNING`) with the answer embedded in the fresh agent's prompt. Re-activation rewrites the marker to `<<RUNNING#id owner=agent job=pending since=... task: ...>>` — the same `job=pending` claim rule as step 2, since the fresh agent has no job id until it submits.
6. On success an agent replaces its placeholder with final content and updates memory (`add-job`, `update-config-status`, `add-learning`, `task-note`/Outcome).

## Mode B — human-driven tab (interactive/tricky tasks)

The human opens a Worktrees tab in the sub-project's workdir and invokes on **one** placeholder:

```
/worknote-orchestrate <worknote> #<id>
```

The tab session claims the placeholder (writes `<<RUNNING#id owner=tab:{name} job=pending ...>>`), then works **interactively** with the human — a normal chat-driven debug loop with full conversational bandwidth. On completion it replaces the placeholder and updates memory. Feedback is per-tab; the human schedules attention across tabs.

- **Stamp-on-claim (never-planned worknote).** Ids are normally stamped by planning scans, so on a fresh worknote a `#<id>` target may match **no stamped placeholder or marker at all** — resolution is by id, and a never-planned worknote has nothing for `#<id>` to match. When the lookup finds no stamped `#<id>`, Mode B **lists the un-stamped placeholders** (quoted body snippets) and **asks the human to pick one**; it then stamps **only that one placeholder** with the next id (the `max`-over-three-sources rule under "Placeholder ids") as part of the claim write — it does not stamp the rest of the file (that stays a planning-scan job).
- **Same task-file discipline as Mode A.** Mode B follows the Mode A skeleton's task-file discipline and promotion protocol: on claim, open a fresh Attempt via `task-note <id> ...` (creating `tasks/task-<id>.md` on first claim); record jobs/configs/learnings at the right level as work proceeds; on completion fill the task-file **Outcome** and promote any worknote-level conclusion via `promote-conclusion <id> <text>` (a pointer back to the task file), then READ BACK — bounded-grep MEMORY.md for `tasks/task-<id>.md` under "Validated conclusions" before writing the Outcome's `promoted:` line; on read-back failure retry the promote once, else write `promoted: FAILED (<reason>)` so drift stays visible. This gives a Mode B takeover/restart the same L3 state a Mode A restart relies on.

## Claiming protocol — what makes the modes coexist

- The marker carries an **owner**: `owner=tab:<name>` or `owner=agent`.
- A coordinator **never dispatches a claimed placeholder** (any `RUNNING`/`BLOCKED` marker with a live owner).
- A tab invocation on an **agent-claimed** placeholder **warns and offers takeover**; on takeover the marker's owner is rewritten to `tab:<name>` and the prior agent's partial state is recovered from memory (`tasks/task-<id>.md` Attempts/Working notes + `blockers.md` + `jobs.md` + `runbook.md`) — the takeover opens a fresh Attempt rather than repeating dead ends.
- **Stale claims** are detected via the `jobs.md` ledger: if a `RUNNING` marker's job id is finished/failed/unknown and no agent is active, the claim is stale and may be resumed or reassigned. A marker still at `job=pending` past a reasonable threshold (`since=` older than the expected submit latency) is **also stale** — it means the claiming session flipped the marker but never submitted a job or filled the id. **The ledger — not the marker — is authoritative for job liveness.**

## Human edits mid-flight — cancel, update, lost-result safety

The human treats the worknote as a live control surface. Every re-scan reconciles markers against the `jobs.md` ledger — **the ledger is authoritative for liveness** — but re-scans differ in what they may do about drift: a **`status` scan only *detects and reports*** it (as `orphaned-job` / `stale-claim` / `done-but-unwritten` rows — no writes, no dispatches); only a **planning scan** (whole-file invocation reaching plan approval) *applies* the cancel/supersede **writes** and **re-dispatches** below:

- **Cancel = delete the marker.** A ledger-RUNNING job whose marker has vanished is treated as **cancelled**: a **planning scan** appends a `cancelled` row to `jobs.md` (a `status` scan only flags it as `orphaned-job`). The same cancelled row is written by an agent that re-greps and can't find its own marker — that is the agent's own "results never lost" accounting, not a `status` write. The coordinator may *optionally* kill the underlying job, but **never auto-kills silently** — it asks in the batched question round.
- **Update = edit the marker's `task:` text.** The `task:` field is the human's intent channel. On a **planning scan** the coordinator compares each RUNNING marker's `task:` against the dispatch recorded in `jobs.md`. Drift means **supersede**: append a `cancelled`/superseded row for the old dispatch and **re-dispatch `#id` with the new task text** (a fresh Attempt). A `status` scan only reports the drift; it never supersedes or re-dispatches. The same comparison on a still-pending stamped placeholder is trivial — the new text is simply what gets dispatched.
- **Editing prose anywhere else is always safe** and requires nothing from agents.

### Locate-by-id marker writes (edit resilience)

An agent must not trust a marker string memorized at dispatch time — the human may have reworded it. At **write time** (success or blocker):

1. Re-grep the worknote (multiline) for `<<(RUNNING|BLOCKED)#<id>(\s[^<>]*)?>>` — the agent's **own** marker only. The `(\s[^<>]*)?` boundary after the id prevents id-prefix collisions (a search for `#3` must not match `<<RUNNING#30 ...>>`).
2. Read a fresh ±20-line window and `Edit` with the freshly-read exact string — one atomic edit.
3. On `Edit` failure: re-grep once and retry. If still failing, fall through to "Results are never lost".

### Results are never lost

If the marker is missing/cancelled or the worknote edit ultimately fails, the agent **still records everything in memory** (`add-job` result pointer, `add-learning`, task-file Outcome) and returns `#<id> done (worknote not updated: <reason>)`. The coordinator surfaces these lines in its summary so the human can paste the conclusion manually if wanted. A vanished worknote write never costs a result.

## `status` invocation — cheap read-only dashboard

`/worknote-orchestrate <worknote> status` scans markers, cross-checks `jobs.md` (ledger authoritative for liveness), and prints **one table** — **no writes, no dispatches, no id-stamping**. This makes habitual re-invocation safe and backs the "worknote is the dashboard" claim with a reconciled view.

Columns: **id · state · owner · job id · age**. An un-stamped `pending` placeholder has no id yet, so its `id` cell prints the sentinel `—`. States:

| State | Meaning |
|---|---|
| `pending` | unclaimed placeholder (id-stamped, or un-stamped and awaiting the next planning scan) |
| `running` | live `RUNNING` marker with a live ledger job |
| `blocked` | `BLOCKED` marker, no answer yet |
| `blocked+answered` | `BLOCKED` marker with an `A:`/`blockers.md` answer — re-activatable |
| `stale-claim` | `RUNNING` marker but its ledger job is finished/failed/unknown — resumable/reassignable |
| `orphaned-job` | ledger-RUNNING job with no marker in the worknote (human deleted it → cancel candidate) |
| `done-but-unwritten` | memory/task-file shows the result recorded but the marker was never replaced |
| `promotion-drift` | a task file's Outcome claims `promoted:` but MEMORY.md has no "Validated conclusions" bullet pointing at `tasks/task-<id>.md` — detected, never fixed, by `status` (like `done-but-unwritten`) |

`status` never resolves any of these — it only reports. Acting on them happens in the next whole-file or `#id` invocation.

## Risk-based mode selection (at plan time)

Classify each needs-work placeholder, driven by memory:

| Classification | Criteria | Recommended mode |
|---|---|---|
| **autonomous** | Config marked `working` in `configs.md`; pure data collection; recipe present in `runbook.md`. | Mode A (parallel agents) |
| **interactive-risk** | Unvalidated config (`untested`/`failed`); first bring-up; known-flaky area per runbook. | Mode B, or serial Mode A with the human present |

Rule of thumb: **a config marked `working` in `configs.md` is safe to parallelize.** Present the recommended mode per placeholder in plan mode; the human may override.

## Canary-then-fan-out policy

For a family of similar jobs (e.g. a sweep from a new baseline):

1. Run **one canary interactively** (Mode B) until its config reaches `working` in `configs.md`.
2. **Only then** fan out the remaining points as parallel Mode A agents.

This spends the expensive human iteration once, not N times — directly addressing "config broken from the beginning."

## Blocker feedback & re-activation

Resumption is **stateless for the agent but stateful for the task** — the original agent is gone, but everything needed to continue already lives in memory (`tasks/task-<id>.md` Attempts/Working notes, `blockers.md` question + evidence + job id linked by `task file:`, `jobs.md`, `runbook.md`) plus the placeholder marker. A re-dispatch reads the task file and opens Attempt N+1, so it never repeats a prior dead end. The human's answer reaches a blocked sub-task by any of three converging paths:

1. **Live batch** — the coordinator is still open: batch all blockers into one `AskUserQuestion` round, write each answer to `blockers.md` via research-memory `answer-blocker`, and immediately re-dispatch with the answer in the fresh agent's prompt.
2. **Edit-and-rerun (async)** — the human appends the answer inline (`<<BLOCKED#id ... Q: ... A: {guidance}>>`) or fills `Answer:` in `blockers.md`, then re-invokes (whole file or `#id`) from any tab. The scan phase treats **BLOCKED-with-answer as re-activatable** (dispatch a fresh agent with original task + Q + answer + memory). **BLOCKED-without-answer** is listed in the plan summary as *awaiting input* and is **never silently re-run**.
3. **Takeover** — the human opens a tab in the blocked workdir and invokes on `#id` (Mode B); the session loads the blocker entry and continues interactively.

All three converge on the same memory records, so they can be mixed freely within one project.

## Resumability

Agents submit jobs, record ids in `jobs.md`, and **may end their turn** — nothing requires an agent to outlive its jobs. Re-invoking the orchestrator (from any tab, any time) resumes `RUNNING` placeholders by checking the ledger and querying job status. Optional, not required by the core flow: **Worktrees cron** to poll job status and re-invoke; **Slack DM** to notify the human when a blocker is recorded.

## Placeholder-agent dispatch skeleton (Mode A)

Dispatch a `general-purpose` Agent per needs-work placeholder; the prompt instructs it to `cd` into the target workdir first. Fill the bracketed fields:

```
You are a placeholder-agent completing ONE worknote placeholder. You run autonomously and
NEVER block on human input.

Working directory: <absolute target workdir>   (cd here first)
Worknote: <absolute worknote path>
Placeholder id: #<id>
Task: <the placeholder's inner text / approved strategy>
Answer from prior blocker (if re-activation): <human answer, or "none">

Steps:
1. cd <workdir>. Bounded-read ./research-memory/MEMORY.md (≤150 lines) for current ground truth,
   AND ./research-memory/tasks/task-<id>.md if it exists (the task's restartable state — prior
   attempts, dead ends, working notes). For anything larger, call the research-memory skill's
   show/read; do not slurp files.
2. Open a NEW attempt: call research-memory `task-note <id> ...` to start a `### Attempt N` section
   (creates tasks/task-<id>.md from template on first claim). Attempt N+1 must NOT repeat attempt N's
   dead ends recorded in the file.
3. Run the task (submit/monitor/collect the job per ./research-memory/runbook.md). Your marker was
   claimed with `job=pending`; as soon as you have a real job id, record it via `add-job` (step 4) and
   then update your marker's `job=` field from `pending` to the real id — a locate-by-id write (step 5
   procedure). This is what makes stale-claim detection work: a marker left at `job=pending` reads as
   stale.
4. Record EVERYTHING via the research-memory skill (skill composition — do not hand-edit memory).
   Promotion protocol — push each fact to exactly the right level:
   - `add-job` when a job is submitted or its status changes (evidence pointer required)  [L2 jobs].
   - `update-config-status <id> <status>` on a verified success/failure  [L2 configs].
   - `add-learning` for any reusable environment/pitfall knowledge  [L2 runbook].
   - `task-note <id> ...` for attempt outcome, next step, partial results  [L3 task file].
   - A validated conclusion the whole worknote depends on → `promote-conclusion <id> <text>` [L1]
     (appends one MEMORY.md "Validated conclusions" bullet with a pointer back to tasks/task-<id>.md).
     Nothing else goes to L1.
5. Locate-by-id marker write (the human may have reworded/moved/deleted your marker):
   re-grep the worknote (multiline) for `<<(RUNNING|BLOCKED)#<id>(\s[^<>]*)?>>` — YOUR marker only —
   read a fresh ±20-line window, and Edit with the freshly-read exact string (one atomic edit).
   On Edit failure: re-grep once and retry.
6a. On SUCCESS: replace your located marker with the FINAL content (conclusions only; details stay
    in memory). If the worknote depends on a validated conclusion, promote it via
    `promote-conclusion <id> <text>`, then READ BACK: bounded-grep MEMORY.md for `tasks/task-<id>.md`
    under "Validated conclusions". Only once the read-back confirms the bullet landed, fill the
    task-file Outcome's `promoted:` line. If the read-back fails, retry `promote-conclusion` once;
    if it still fails, write `promoted: FAILED (<reason>)` in the Outcome so the drift is VISIBLE
    rather than silently claimed. Fill the rest of the task-file Outcome (conclusion + what was promoted).
6b. On BLOCKER: call research-memory `add-blocker` to append a blockers.md entry (id, timestamp,
    workdir, placeholder ref, task file, Question, Evidence), flip your located marker to
    `<<BLOCKED#id owner=agent ... Q: {question}>>` (keep it a valid <<...>> placeholder — no nested
    < or >), record the blocker id in the task file's Attempt, and RETURN. Do not wait.
6c. If your marker is GONE (cancelled) or the Edit ultimately fails: results are NOT lost — memory
    and the task file already hold everything. Return "#<id> done (worknote not updated: <reason>)".
7. Return ONE status line: "#<id> done" | "#<id> done (worknote not updated: <reason>)"
   | "#<id> BLOCKED: <question>" | "#<id> RUNNING: job <id>".
```

## Roles

| Role | Responsibilities |
|---|---|
| **Human** | Owns worknote structure + prose; answers batched blockers; runs Mode B for tricky work; decides mode overrides at plan time. |
| **Coordinator** (whole-file session) | Scan, id-stamp, classify, plan; set MEMORY.md "Current focus" via `set-focus` at plan approval and refresh it in the completion/blocker round; reconcile markers vs `jobs.md` (cancel/supersede); dispatch placeholder-agents; batch blocker feedback into ONE question round; fill fill-from-data placeholders; re-dispatch answered/superseded blockers; surface any `done (worknote not updated)` lines in the summary. |
| **Placeholder-agent** (subagent, per workdir) | `cd` workdir; bounded-read memory + `tasks/task-<id>.md`; open a fresh Attempt; run jobs; record everything via research-memory (promotion protocol); locate-by-id then replace its placeholder on success or flip to `BLOCKED`; never block on human input; never lose a result if the marker vanished. |
| **Shared memory** ([[research-memory]]) | Ground truth: configs, runbook, job ledger, blockers — the only cross-session channel. |

## End-to-end note

A whole-file round: human adds placeholders → coordinator scans + classifies → plan-mode approval of classification + per-placeholder modes → fill-from-data filled directly; autonomous needs-work fanned out as parallel Mode A agents; interactive-risk recommended to Mode B (canary first, then fan out). Agents run jobs, write memory, and either replace their placeholder or flip to `BLOCKED`. The coordinator batches all blockers into one question round, writes answers, and re-dispatches. The worknote ends as conclusions only, with all evidence in memory.
