---
name: research-memory
description: Maintain or query evidence-backed shared memory beside a human worknote, including job histories, configurations, runbooks, blockers, and task records. Use for research-memory actions or explicit references to another worknote's memory; not for general note-taking or unrelated artifact searches.
metadata:
  author: Chunwei Yan
  version: 0.8.0
---

# Research memory

Keep detailed evidence in `<worknote-dir>/<Base>.memory/` while the human worknote contains conclusions. Participating workdirs may link that store as `./research-memory`. The companion [worknote-orchestrate](../worknote-orchestrate/SKILL.md) uses it for restartable tasks.

## Essential contracts

- `MEMORY.md` is a curated index, at most 150 lines. Read it first, then retrieve only the details needed. Current focus is at most five forward-looking bullets; it may be empty.
- `configs.md` and `runbook.md` are mutable. `jobs.md` is an append-only history of observed job states; `blockers.md` is append-only except for filling the latest entry's empty Answer once. Remove template examples on first real use, without changing historical records.
- `tasks/task-<id>.md` preserves allocated IDs and restart state. The active Attempt is mutable by its owner; closed Attempts and a completed final Outcome are immutable. See the task-note action for permitted updates.
- Record evidence for factual claims and timestamps where the schema specifies them. A missing fact stays unknown. Task cancellation does not prove job termination.
- Keep reusable helpers in `scripts/`, with a citation in runbook Collect. Do not silently reorganize unrelated files discovered during a query.
- Serialize shared-file writes within a coordinator. Different sessions must agree on a writer or explicit handoff before overlapping writes. Exact edits and read-back reduce mistakes but do not provide cross-session locking or multi-file transactions.

## Select an operation

Read only the indicated reference, then the target action's section.

| Request | Reference |
|---|---|
| `init <worknote>`, `link` | [Action contracts](references/actions.md#setup) |
| `task-note`, `add-job`, `update-config-status` | [Action contracts](references/actions.md#task-and-job-records) |
| `add-learning`, `add-script`, `add-blocker`, `answer-blocker` | [Action contracts](references/actions.md#learnings-and-blockers) |
| `promote-conclusion`, `set-focus` | [Action contracts](references/actions.md#curated-index) |
| `query [<worknote>] <question>`, `show-summary` | [Queries](references/queries.md) |

Templates in [templates/](templates/) define the file shapes; create task files lazily. Existing stores need no migration. Resolve an explicitly named store first, otherwise the local symlink; for init derive the sibling store from the worknote. If `link` has no uniquely identified target, ask for it. Do not guess among projects.

## Execution and dispatch

Resolve resources relative to this installed SKILL.md, not the process cwd or an environment variable. Pass absolute store, workdir, template, and reference paths to workers.

Prefer a permitted subagent for a substantial memory operation or query when it saves context. Delegate a bounded operation with its arguments and relevant action section; do not paste every action into the prompt. When delegation is unavailable, forbidden, or impractical for a small operation, perform bounded direct reads and serial exact edits. Report serial execution when it changes the requested parallel workflow.

The host's read/search, exact-edit, subagent, and user-input capabilities may have different names in Claude Code and Codex. Use available equivalents. Reuse existing authorization; ask only for missing information, expanded scope, or required permissions. A worker reports permission failures to its coordinator rather than repeatedly retrying.

For writes: validate prerequisites, reread the affected records, apply the smallest edit, then verify the action's postconditions. If a multi-file operation partially fails, report what persisted and the repair needed; never claim atomicity. Return a concise confirmation (normally three lines or fewer) with changed records and any remaining issue. Queries return the answer with evidence, not a diff hint.
