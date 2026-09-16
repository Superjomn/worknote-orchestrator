# Blockers

<!-- APPEND-ONLY entries. The `Answer:` field is the only mutable part of an entry. -->
<!-- One entry per open question for the human. Every entry carries an evidence pointer. -->
<!-- A BLOCKED placeholder marker in the worknote references the blocker id here. -->
<!-- Re-blocking appends a NEW entry with the same id. Fill only the latest empty Answer once. -->
<!-- If the latest Answer is filled, refuse overwrites even when older entries are unanswered. -->

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
