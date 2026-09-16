# Context, scanning, and stable IDs

## Scanner

Resolve the absolute path of [wn_scan.py](../scripts/wn_scan.py) from this installed skill:

```text
python3 <absolute-script-path> <worknote> --memory <store> [--id N] [--format json|table]
```

The script is read-only. JSON returns worknote, duplicate_ids, next_id, next_id_sources, context_blocks, and placeholders. Each placeholder includes its body, ID, line, state, owner/attempt/fingerprint/job/since, task/question/answer/blocker_format, section, context_chain, effective_dir, directives, and context_drift. `--id N` returns only the selected placeholder object; use this for dispatch hiding. Duplicate IDs must be resolved before claims; an ambiguous `--id` fails rather than picking one. Exit codes are 0 for success/help and 2 for usage/parse failures.

Table output is a marker view, not the full reconciled status dashboard. The coordinator adds ledger/task reconciliation from [Lifecycle](lifecycle.md#status). Context drift is computed only for claimed RUNNING/BLOCKED markers with a recorded latest Attempt context; null is not evidence that an unrecorded context is unchanged.

## Grammar and scoped context

Match `<<[^<>]+?>>` with multiline/DOTALL semantics. Nested angle brackets are unsupported; use words such as “gt” or put lengthy material in memory and cite it. Partition matches after scanning: a body whose first non-whitespace character is `!` is persistent context; all other matches are tasks or markers. Matches inside code fences still count as placeholders.

For a context block at line L, find the nearest ATX heading at or above L. Headings use one to six `#` characters, at most three leading spaces. Ignore headings inside backtick/tilde fences or placeholder bodies. Setext underlines and YAML separators do not establish scopes.

The block spans from L to just before the next heading at the same or a shallower level, or EOF. A block before any heading has level 0 and spans to EOF; a block below `# Title` is scoped to that title. Context never applies to placeholders above its starting line.

A placeholder inherits all blocks whose spans contain its line, ordered by source line (outermost to innermost). Pass only that chain, never sibling-section context. Later blocks override earlier defaults; the placeholder's own directives override inherited defaults:

| Hint | Meaning |
|---|---|
| `@dir:<workdir>` | Working directory; resolve to an absolute path before dispatch |
| `@memory` | Existing evidence only; no jobs |
| `@run` | Work likely requires execution |

These are hints interpreted during planning, not an executable DSL. Within each body, process directives left-to-right: the final @dir wins, and the final @memory or @run evicts the other mode. Across bodies, later blocks and the task override earlier defaults. Resolve any remaining ambiguity in the human's prose before execution.

Canonical task-record context is block texts with whitespace collapsed, joined by ` | `, or `none` for an empty chain. Store this exact form in each Attempt's `- context:` line; source headings may accompany the dispatch but are not part of that serialized value. Editing or moving context can invalidate an active dispatch; reconcile before writes.

Example: a preamble block applies to both Experiment A and Experiment B; a block under `# Experiment A` stops at `# Experiment B`. A task in A receives the preamble plus A's applicable blocks, never B's.

## Stable IDs

The next ID is one greater than the maximum of worknote marker IDs, `tasks/task-<id>.md` filenames, and BLOCKED IDs in blockers.md. Body references like “issue #123” and context blocks do not contribute. Do not allocate from a scan without the memory store when an existing store is in use.

`next_id` is a preview, never an allocation. Reserve with:

```text
python3 <absolute-skill-dir>/scripts/wn_allocate.py <worknote> --memory <store> [--count N]
```

The helper exclusively creates task-file reservations and returns `{"reserved_ids": [N]}`.
Concurrent allocators cannot reserve the same ID. An interruption may burn an ID; even an empty
reservation file remains permanently reserved. The helper never changes the worknote.
Initialize each reserved Brief through task-note, then stamp the exact pending placeholder.
A competing claim must be resolved before dispatch; never overwrite it with your reserved ID. If stamping fails, keep the record as an unused reservation; IDs are never recycled. This also applies to fill-from-data tasks and existing stamped IDs that lack records. Do not dispatch until reservation and stamping are verified. A planning-only or status scan never reserves or stamps.

For Mode B, first look up the stamped ID. If absent, list unstamped snippets and ask the human to select a target; assign that selection an actually reserved ID, report it, and stamp only that placeholder. Never interpret the requested number as a scan-order ordinal.

When the scanner cannot run, read-only status may use bounded manual inspection. Allocation and guarded publication require their helpers; stop the affected write instead of guessing a fingerprint or reusing a preview ID.

## Guarded publication

With `--id N`, supply all three of `--expect-attempt TOKEN`, `--expect-owner OWNER`, and
`--expect-fingerprint HASH` captured at dispatch. A failed guard exits 2 without emitting a
placeholder. Fingerprints cover exact task text, ordered context texts with preserved block
boundaries, and effective directives; marker moves and job updates alone do not change them.
See [Lifecycle](lifecycle.md#publication-guard-and-completion) for the check/write sequence.
