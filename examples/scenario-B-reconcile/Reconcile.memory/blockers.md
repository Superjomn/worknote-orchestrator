# Blockers

<!-- APPEND-ONLY entries. The `Answer:` field is the only mutable part of an entry. -->
<!-- One entry per open question for the human. Every entry carries an evidence pointer. -->
<!-- A BLOCKED placeholder marker in the worknote references the blocker id here. -->
<!-- A re-blocked task appends a NEW entry with the same id; `answer-blocker` fills the latest one. -->

## Entry format

```
### BLOCKED#<id> — <short title>
- timestamp: <YYYY-MM-DD HH:MM>
- workdir: <path or worktree name>
- placeholder ref: <worknote path>#<id>
- task file: <./tasks/task-<id>.md — the per-task working state that raised this>
- Question: <the specific question for the human>
- Evidence: <job id / log path / dashboard URL that motivates the question>
- Answer: <empty until the human or coordinator fills it>
```

## Entries
_(append new blockers below)_

### BLOCKED#4 — dp=16 OOM
- timestamp: 2026-07-09 09:10
- workdir: workdir
- placeholder ref: Reconcile.md#4
- task file: ./tasks/task-4.md
- Question: OOM at dp=16 — reduce batch or skip?
- Evidence: mock-0004-oom, 2026-07-09
- Answer:

### BLOCKED#5 — dp=32 image tag
- timestamp: 2026-07-09 09:12
- workdir: workdir
- placeholder ref: Reconcile.md#5
- task file: ./tasks/task-5.md
- Question: which image tag to use for the dp=32 point?
- Evidence: tasks/task-5.md, 2026-07-09
- Answer: use nano:0.3
