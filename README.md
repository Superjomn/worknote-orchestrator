# worknote-orchestrator

Two skills for filling human-owned worknote placeholders from existing evidence or real jobs, with shared research memory and batched feedback. The instructions support Claude Code and Codex; the existing package is a Claude Code plugin.

- **worknote-orchestrate** coordinates a whole worknote, works one named task interactively, or reports a read-only dashboard. Persistent `<<! ... >>` context blocks apply only to their Markdown scopes. Workers receive only their task's inherited context.
- **research-memory** stores evidence, configs, job observations, runbooks, blockers, and restartable task records beside the worknote. Its index stays small; action details and queries load from references only when needed.

## Install and use

For Claude Code:

```text
/plugin marketplace add Superjomn/worknote-orchestrator
/plugin install worknote-orchestrator@worknote-orchestrator
```

For Codex, place both sibling directories from `skills/` in your configured skill location, keeping each skill's references, templates, and scripts together. Invoke by skill name using the host's supported syntax. No Claude environment variable is required: resource paths resolve from the installed skill directory.

Typical requests (Claude slash-command examples):

```text
/research-memory init /path/to/MyStudy.md
/research-memory link
/worknote-orchestrate /path/to/MyStudy.md
/worknote-orchestrate /path/to/MyStudy.md #3
/worknote-orchestrate /path/to/MyStudy.md status
```

Init creates `MyStudy.memory/` beside the existing worknote. Link connects a workdir's `./research-memory` to that store and excludes the link through git's local info/exclude. A new, unvalidated recipe normally starts with one interactive canary before parallel execution.

## Operating contracts

The worknote contains conclusions; memory holds evidence and execution details. IDs are reserved in task records even for fill-from-data tasks and never reused. Active Attempts hold progress; closed Attempts and completed Outcomes are preserved.

Before changing a marker, the writer verifies its owner, Attempt, task text, and scoped context. Results are saved before publication. Deleted or changed markers invalidate publication intent; they do not prove the underlying jobs stopped. Terminal ledger entries require evidence. Status and memory queries never repair or mutate data.

Workers are optional: when permitted and available, independent computation may run in parallel while the coordinator serializes shared writes. Otherwise the same workflow runs serially with bounded reads. Independent tabs need explicit handoff for overlapping writes. Exact edits and read-back checks reduce errors but provide neither distributed locking nor multi-file atomicity.

Existing commands, marker grammar, store layout, and scanner CLI/JSON remain compatible. Existing stores need no migration; legacy Attempts without ownership snapshots require reconciliation before publication. `complete-report` is an optional source of content-formatting guidance.

## Documentation and validation

Start with [worknote-orchestrate](skills/worknote-orchestrate/SKILL.md) or [research-memory](skills/research-memory/SKILL.md). Each entrypoint links the references needed for a selected operation.

Run deterministic scanner checks with `bash tests/wn-scan/run.sh`. See [mock-memory cases](tests/mock-memory/CASES.md) for isolated agent-executed actions followed by file-state assertions. Fixture setup and assertions do not themselves execute the skill. Use a fresh scratch directory for each case.

Author: Chunwei Yan.
