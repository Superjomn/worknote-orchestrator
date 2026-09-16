---
name: worknote-orchestrate
description: Fill actionable worknote placeholders from existing evidence or coordinated jobs, using scoped persistent context and shared research memory. Use for worknote orchestration, a named placeholder, or its status dashboard; not for general report editing without worknote tasks.
metadata:
  author: Chunwei Yan
  version: 0.8.0
---

# Worknote orchestration

Turn human-owned `<<...>>` placeholders into conclusions, keeping evidence and restart state in [research-memory](../research-memory/SKILL.md). Persistent `<<! ... >>` blocks supply scoped input; never stamp, dispatch, replace, or echo them as conclusions. The human may edit the worknote throughout execution.

## Choose a workflow

| Invocation | Behavior | Read next |
|---|---|---|
| `/worknote-orchestrate <worknote>` | Coordinate approved tasks; parallelize independent jobs when permitted | [Context and scanning](references/context-scanning.md), then [Lifecycle](references/lifecycle.md) |
| `/worknote-orchestrate <worknote> #<id>` | Work one task interactively (Mode B) | [Lifecycle](references/lifecycle.md); consult scanning rules for context/ID resolution |
| `/worknote-orchestrate <worknote> status` | Reconcile a read-only dashboard | [Status](references/lifecycle.md#status) |

For a dispatched worker read [Worker dispatch](references/worker-dispatch.md); pass only the selected placeholder's context chain and relevant memory action instructions. Do not load every reference or the whole worknote into every worker.

## Essential workflow

1. Resolve the worknote, sibling memory store, and authorized workdirs. Use the read-only scanner at `scripts/wn_scan.py` relative to this skill. Always pass the known memory store for ID allocation and context-drift checks.
2. Classify each task as fill-from-data or needs-work. An inherited or local `@memory` forbids jobs. Prefer interactive canary work for unvalidated configs; validated recipes may support independent parallel tasks. Config success alone does not authorize resource use or prove every sweep point safe.
3. Present unresolved choices and the intended work. Reuse approval already given; do not force another plan-mode round. Respect the host's current planning/execution mode and permissions.
4. Reserve IDs in task records, claim authorized targets, and execute under the [lifecycle](references/lifecycle.md). Fill-from-data tasks also get records and publication checks. Batch worker blockers through the coordinator; workers record and return rather than independently interrupting the human.
5. Save evidence/results before publication, verify ownership and unchanged intent, then replace only the exact current marker. Preserve results if the worknote changed. Refresh Current focus, including clearing it when the round finishes.

## Boundaries and portability

- Conclusions belong in the worknote; commands, intermediate data, job receipts, and evidence belong in memory. Match surrounding language and structure. If available and relevant, complete-report may supply content/figure/math guidance, but is not required and does not control execution or add approval gates.
- Resolve resources from the installed skill directory and pass absolute paths. Do not require `CLAUDE_PLUGIN_ROOT` or literal tool names. Use the host's search/read, exact-edit, delegation, and user-input capabilities.
- Prefer permitted workers for independent work. If delegation is unavailable, execute serially with bounded reads and report the changed scheduling. Do not create user-owned tasks or send external notifications as a substitute.
- Serialize marker/ID allocation and shared-memory edits within the coordinator. Route worker writes through that writer. Independent tabs require explicit handoff before overlapping writes; no locking helper is included, so reread/read-back checks cannot guarantee race-free cross-session writes.
- A missing marker cancels publication intent, not the underlying job. Never fabricate a terminal ledger state. A status call makes no writes and starts no execution workers.
