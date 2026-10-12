# worknote-orchestrator

Two skills for filling human-owned worknote placeholders from existing evidence or real jobs, with shared research memory and batched feedback. The instructions support Claude Code and Codex; the existing package is a Claude Code plugin.

- **worknote-orchestrate** coordinates a whole worknote, works one named task interactively, or reports a read-only dashboard. Persistent `<<! ... >>` context blocks apply only to their Markdown scopes. Workers receive only their task's inherited context.
- **research-memory** stores evidence, configs, job observations, runbooks, blockers, and restartable task records beside the worknote. Its index stays small; action details and queries load from references only when needed.

## Quickstart

This example uses an installed, authenticated Claude Code, Git, Bash, and Python 3.10+.
The Python helpers use only the standard library; there is no pip or npm install step.
Skills perform the memory and worknote edits through your agent; the scanner alone does
not fill placeholders.

In a terminal, clone the plugin and create a fresh demo directory with local evidence:

```bash
git clone https://github.com/Superjomn/worknote-orchestrator.git
cd worknote-orchestrator
plugin_dir="$PWD"
demo_dir=$(mktemp -d)
cd "$demo_dir"
cat > measurements.txt <<'EOF'
baseline: 1200 tok/s
candidate: 1500 tok/s
EOF
cat > Study.md <<'EOF'
# Throughput comparison

<<! @memory Use measurements.txt beside this worknote as the evidence. >>

## Result
<<Report the baseline and candidate throughput and the percentage improvement. Cite the evidence file.>>
EOF
claude --plugin-dir "$plugin_dir"
```

`--plugin-dir` loads the local checkout for this session. Plugin skills use the
`/plugin-name:skill-name` namespace ([Claude Code plugin documentation](https://code.claude.com/docs/en/plugins)).
Inside Claude Code, send these requests **one at a time**, waiting for each to finish:

```text
/worknote-orchestrator:research-memory init Study.md
/worknote-orchestrator:worknote-orchestrate Study.md
/worknote-orchestrator:worknote-orchestrate Study.md status
```

Init creates the five index/ledger files in `Study.memory/`. Orchestration reserves
task #1, records an owned Attempt and its result in `Study.memory/tasks/task-1.md`, and
replaces the Result placeholder. The `@memory` context remains in the worknote and
forbids submitting jobs. A representative result (wording may vary) is:

```markdown
## Result
The candidate reaches 1500 tok/s versus the baseline's 1200 tok/s, a 25% improvement
(measurements.txt).
```

Status should report no remaining actionable placeholders. Exit Claude Code, then
verify from the same terminal:

```bash
cat Study.md
test -f Study.memory/tasks/task-1.md
python3 "$plugin_dir/skills/worknote-orchestrate/scripts/wn_scan.py" \
  Study.md --memory Study.memory --format table
```

The scanner prints only its header after completion:

```text
id · state · owner · job · age · ctx
```

The demo uses the sibling memory store directly. Use `research-memory link` when
joining it from a Git worktree; linking is optional for this example.

## Install and use

For Claude Code:

```text
/plugin marketplace add Superjomn/worknote-orchestrator
/plugin install worknote-orchestrator@worknote-orchestrator
```

For Codex, place both sibling directories from `skills/` in your configured skill location, keeping each skill's references, templates, and scripts together. Invoke by skill name using the host's supported syntax. No Claude environment variable is required: resource paths resolve from the installed skill directory.

Typical requests (Claude plugin slash-command examples):

```text
/worknote-orchestrator:research-memory init /path/to/MyStudy.md
/worknote-orchestrator:research-memory link
/worknote-orchestrator:worknote-orchestrate /path/to/MyStudy.md
/worknote-orchestrator:worknote-orchestrate /path/to/MyStudy.md #3
/worknote-orchestrator:worknote-orchestrate /path/to/MyStudy.md status
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

## Lifecycle helper checks

```bash
python3 -B -m unittest discover -s tests/lifecycle -v
```

These regressions cover durable concurrent ID allocation, stale-attempt guards, task/context
changes, and scanner edge cases. See `tests/lifecycle/CASES.md` for agent-executed scenarios.
`wn_scan.py next_id` is a read-only preview; reserve every new ID with `wn_allocate.py`.
Legacy markers remain readable but must be reconciled into a fresh owned attempt before writes.
