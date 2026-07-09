---
name: worknote-orchestrate
description: "Fill <<...>> placeholders in a human worknote by classifying each as fill-from-data or needs-work, then running the needs-work ones as jobs across parallel coordinator-driven agents (Mode A) or a human-driven tab (Mode B), with a claiming protocol, worknote-embedded state markers, and ONE batched human-feedback round. Layers on complete-report and records everything via research-memory. TRIGGER when: user runs /worknote-orchestrate, says \"fill worknote placeholders\", \"run worknote jobs\", \"orchestrate the worknote\", or wants to execute + fill placeholders that require running jobs."
author: Chunwei Yan
version: 0.1.0
user_invocable: true
---

# worknote-orchestrate — Run + Fill Worknote Placeholders

Orchestrate a human worknote whose `<<...>>` placeholders may require **running jobs**, not just generating text. It layers execution semantics on top of `complete-report` and uses [[research-memory]] as the shared ground truth and cross-session channel.

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
pending  --> running   (claimed: agent dispatch or tab invocation)
running  --> done       (success — placeholder replaced with final content)
running  --> blocked    (failure needing human input)
blocked  --> blocked+ans (human writes answer inline or in blockers.md)
blocked+ans --> running  (re-activated with the answer embedded in a fresh agent's prompt)
blocked  --> running    (human takeover — Mode B in that workdir)
running  --> running    (re-invocation resumes via the jobs.md ledger)
```

> **Markers stay valid `<<...>>` placeholders** — no nested `<` or `>` inside them — so `complete-report` (and this skill's own scan) still find them. Example markers:
>
> ```
> <<RUNNING#3 owner=tab:duckling-pie job=srun-8812345 since=2026-07-09 task: sweep dp=4>>
> <<BLOCKED#3 owner=agent since=2026-07-09 task: sweep dp=4 Q: OOM at dp=4 — reduce batch or skip? A: skip, note in report>>
> ```

## Mode A — coordinator-driven parallel agents (autonomous tasks)

One coordinator session runs the whole-file invocation:

1. Scan + classify + plan-mode approval (per Classification and Risk-based selection below).
2. Dispatch each approved needs-work placeholder to a **placeholder-agent** — a subagent whose `cwd` is the target workdir. Independent placeholders are dispatched **in parallel** (one message, multiple `Agent` calls). Before dispatching, flip the placeholder to `<<RUNNING#id owner=agent job=... since=... task: ...>>`.
3. Placeholder-agents **never block on human input.** On a blocker they: write a structured `blockers.md` entry (via research-memory), flip the placeholder to `<<BLOCKED#id ...>>`, and return a status line.
4. The coordinator collects completions and **serializes ALL pending blockers into a single `AskUserQuestion` round** — one interrupt instead of N scattered ones.
5. Each answer is written into its blocker's `Answer:` field (and inline into the marker), and the affected placeholders are immediately re-dispatched (`BLOCKED` → `RUNNING`) with the answer embedded in the fresh agent's prompt.
6. On success an agent replaces its placeholder with final content and updates memory (`add-job`, `update-config-status`, `add-learning`).

## Mode B — human-driven tab (interactive/tricky tasks)

The human opens a Worktrees tab in the sub-project's workdir and invokes on **one** placeholder:

```
/worknote-orchestrate <worknote> #<id>
```

The tab session claims the placeholder (writes `<<RUNNING#id owner=tab:{name} ...>>`), then works **interactively** with the human — a normal chat-driven debug loop with full conversational bandwidth. On completion it replaces the placeholder and updates memory. Feedback is per-tab; the human schedules attention across tabs.

## Claiming protocol — what makes the modes coexist

- The marker carries an **owner**: `owner=tab:<name>` or `owner=agent`.
- A coordinator **never dispatches a claimed placeholder** (any `RUNNING`/`BLOCKED` marker with a live owner).
- A tab invocation on an **agent-claimed** placeholder **warns and offers takeover**; on takeover the marker's owner is rewritten to `tab:<name>` and the prior agent's partial state is recovered from memory (`blockers.md` + `jobs.md` + `runbook.md`).
- **Stale claims** are detected via the `jobs.md` ledger: if a `RUNNING` marker's job id is finished/failed/unknown and no agent is active, the claim is stale and may be resumed or reassigned. **The ledger — not the marker — is authoritative for job liveness.**

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

Resumption is **stateless** — the original agent is gone; everything needed to continue already lives in memory (`blockers.md` question + evidence + job id, `jobs.md`, `runbook.md`) plus the placeholder marker. The human's answer reaches a blocked sub-task by any of three converging paths:

1. **Live batch** — the coordinator is still open: batch all blockers into one `AskUserQuestion` round, write each answer to `blockers.md`, and immediately re-dispatch with the answer in the fresh agent's prompt.
2. **Edit-and-rerun (async)** — the human appends the answer inline (`<<BLOCKED#id ... Q: ... A: {guidance}>>`) or fills `Answer:` in `blockers.md`, then re-invokes (whole file or `#id`) from any tab. The scan phase treats **BLOCKED-with-answer as re-activatable** (dispatch a fresh agent with original task + Q + answer + memory). **BLOCKED-without-answer** is listed in the plan summary as *awaiting input* and is **never silently re-run**.
3. **Takeover** — the human opens a tab in the blocked workdir and invokes on `#id` (Mode B); the session loads the blocker entry and continues interactively.

All three converge on the same memory records, so they can be mixed freely within one project.

## Resumability

Agents submit jobs, record ids in `jobs.md`, and **may end their turn** — nothing requires an agent to outlive its jobs. Re-invoking the orchestrator (from any tab, any time) resumes `RUNNING` placeholders by checking the ledger and querying job status. Optional, not required by the core flow: **Worktrees cron** to poll job status and re-invoke; **Slack DM** to notify the human when a blocker is recorded.

## Placeholder-agent dispatch skeleton (Mode A)

Dispatch a `general-purpose` Agent per needs-work placeholder, `cwd` = target workdir. Fill the bracketed fields:

```
You are a placeholder-agent completing ONE worknote placeholder. You run autonomously and
NEVER block on human input.

Working directory: <absolute target workdir>   (cd here first)
Worknote: <absolute worknote path>
Placeholder id: #<id>
Task: <the placeholder's inner text / approved strategy>
Answer from prior blocker (if re-activation): <human answer, or "none">

Steps:
1. cd <workdir>. Bounded-read ./research-memory/MEMORY.md (≤150 lines) for current ground truth.
   For anything larger, call the research-memory skill's show/read, do not slurp files.
2. Run the task (submit/monitor/collect the job per ./research-memory/runbook.md).
3. Record EVERYTHING via the research-memory skill (skill composition — do not hand-edit memory):
   - `add-job` when a job is submitted or its status changes (evidence pointer required).
   - `update-config-status <id> <status>` on a verified success/failure.
   - `add-learning` for any new environment/pitfall knowledge.
4a. On SUCCESS: replace the `<<RUNNING#id ...>>` marker in the worknote with the FINAL content
    (conclusions only; details stay in memory). Use Edit with old_string = the exact full marker.
4b. On BLOCKER: call research-memory to append a blockers.md entry (id, timestamp, workdir,
    placeholder ref, Question, Evidence), flip the marker to `<<BLOCKED#id owner=agent ... Q: {question}>>`
    (keep it a valid <<...>> placeholder — no nested < or >), and RETURN. Do not wait.
5. Return ONE status line: "#<id> done" | "#<id> BLOCKED: <question>" | "#<id> RUNNING: job <id>".
```

## Roles

| Role | Responsibilities |
|---|---|
| **Human** | Owns worknote structure + prose; answers batched blockers; runs Mode B for tricky work; decides mode overrides at plan time. |
| **Coordinator** (whole-file session) | Scan, classify, plan; dispatch placeholder-agents; batch blocker feedback into ONE question round; fill fill-from-data placeholders; re-dispatch answered blockers. |
| **Placeholder-agent** (subagent, per workdir) | `cd` workdir; bounded-read memory; run jobs; record everything via research-memory; replace its placeholder on success or flip to `BLOCKED`; never block on human input. |
| **Shared memory** ([[research-memory]]) | Ground truth: configs, runbook, job ledger, blockers — the only cross-session channel. |

## End-to-end note

A whole-file round: human adds placeholders → coordinator scans + classifies → plan-mode approval of classification + per-placeholder modes → fill-from-data filled directly; autonomous needs-work fanned out as parallel Mode A agents; interactive-risk recommended to Mode B (canary first, then fan out). Agents run jobs, write memory, and either replace their placeholder or flip to `BLOCKED`. The coordinator batches all blockers into one question round, writes answers, and re-dispatches. The worknote ends as conclusions only, with all evidence in memory. See the design doc's end-to-end mermaid flow: `design/worknote-orchestrator-design.md` §7 (in the duckling-pie repo).
