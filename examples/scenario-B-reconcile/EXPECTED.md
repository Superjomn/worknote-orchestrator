# EXPECTED — scenario-B-reconcile

Stresses: the **marker state machine** + **`status` reconciliation** (read-only) + **stale-claim
detection** + **blocked→answered re-activation**. Pre-seeded so no Mode A is needed first.

Seeded start (6 stamped markers #1–#6, ids fixed):

| # | marker seed | seeded job | resolves to |
|---|---|---|---|
| 1 | `RUNNING#1 job=mock-0001` | mock-0001 = hang-running | **running** (control) |
| 2 | `RUNNING#2 job=mock-0002` | NO state file | `unknown` → **stale-claim** |
| 3 | `RUNNING#3 job=pending since=2026-06-01` | never submitted | **stale-claim** (never submitted) |
| 4 | `BLOCKED#4 … Q:…` empty Answer | — | **blocked** (awaiting input) |
| 5 | `BLOCKED#5 … Q:… A: use nano:0.3` | — | **blocked+answered** → re-activatable |
| 6 | `RUNNING#6 job=mock-0006` + task-6 Outcome + finished row | mock-0006 = fast-ok/finished | **done-but-unwritten** |

Plus a ledger-`running` job **mock-0009** with **NO marker** → **orphaned-job**.

Run in TWO passes (`./setup.sh` first).

---

## Pass 1 — `/worknote-orchestrate <abs>/Reconcile.md status`  (read-only)

### 1a. Exact reconciliation table
The dashboard prints one row per marker + the orphan, columns **id · state · owner · job id · age**:

| id | state | owner | job id | age |
|---|---|---|---|---|
| #1 | running | agent | mock-0001 | (from since=2026-07-09) |
| #2 | stale-claim | agent | mock-0002 | (unknown id) |
| #3 | stale-claim | agent | pending | (since=2026-06-01, very old) |
| #4 | blocked | agent | — | — |
| #5 | blocked+answered | agent | — | — |
| #6 | done-but-unwritten | agent | mock-0006 | — |
| — | orphaned-job | agent | mock-0009 | (no marker) |

Exact set of states must be `{running, stale-claim×2, blocked, blocked+answered, done-but-unwritten,
orphaned-job}`. The un-stamped-id cell for the orphan prints the sentinel `—`.

### 1b. HEADLINE INVARIANT — status never writes
The worknote AND every memory file are **byte-identical before vs after** the status pass.
Concrete check (run around the status invocation):

```
# before
find Reconcile.md Reconcile.memory -type f -name '*.md' | sort | xargs md5sum > /tmp/b_before.txt
# ... run the status pass ...
# after
find Reconcile.md Reconcile.memory -type f -name '*.md' | sort | xargs md5sum > /tmp/b_after.txt
diff /tmp/b_before.txt /tmp/b_after.txt   # MUST be empty
```

No new task files, no id-stamping, no marker rewrites, no dispatches.

---

## Pass 2 — `/worknote-orchestrate <abs>/Reconcile.md`  (planning scan)

Now writes/dispatches are allowed. Expected effects:

- **#5 blocked+answered → re-activated:** marker flips `BLOCKED#5` → `RUNNING#5` (job=pending →
  real id), submits dp=32 (plan `fast-ok`) → finished → **final content replaces the marker** with
  the dp=32 throughput. `tasks/task-5.md` created with an Attempt citing the answer `use nano:0.3`;
  `configs.md#dp32` → `working`; a `MEMORY.md` Validated-conclusions bullet added (→ task-5.md).
- **#4 blocked, no answer:** listed as *awaiting input* and **left untouched** — never silently
  re-run. (Allowed variant: the coordinator batches #4 into the ONE `AskUserQuestion` round; if the
  human answers there, #4 may then re-activate. Both outcomes are acceptable; a silent auto-run of #4
  is NOT.)
- **#2 / #3 stale-claim:** treated as resumable — the coordinator may re-dispatch them (fresh submit).
  Their markers may return to a live `RUNNING#id job=mock-00NN` (new id ≥ mock-0010) or resolve to
  content; the key assertion is they are **not** treated as live-untouched.
- **#6 done-but-unwritten:** may be reconciled — marker replaced with the already-validated dp=64
  content (1400.0 tok/s). task-6.md Outcome is NOT rewritten (write-once); Attempt 1 unchanged.
- **#1 running:** stays running (mock-0001 is hang-running) unless the human intervenes.
- **orphaned mock-0009:** a planning scan may append a `cancelled` row (cancel candidate) or surface
  it in the batched round; never silently killed.

### Memory invariants after Pass 2
- `jobs.md`: the 5 seed rows are **byte-identical**; only **appended** rows added (new submits /
  status changes). 7 columns each.
- `blockers.md`: append-only preserved; #5's `Answer: use nano:0.3` unchanged; #4's `Answer:` still
  empty unless it was answered in the batched round (then filled on the **latest** #4 entry).
- `configs.md`: dp32 → `working` (evidence = its new mock id). dp64 stays `working`.
- `MEMORY.md`: still **≤150 lines** (`wc -l` ≤ 150); a Validated-conclusions bullet per newly
  validated point, each with a `→ tasks/task-<id>.md` pointer.

---

## Invariants (both passes)
- **Placeholder id monotonicity:** max marker-head id is #6, plus `tasks/task-6.md`, plus blocker
  ids #4/#5 → next placeholder id would be **#7**. (Job-id sequence is separate: max seeded job is
  mock-0009 → next submit is **mock-0010**.)
- **Markers stayed valid `<<...>>`** (no nested `<`/`>`) throughout. Check:
  `grep -oE '<<[^<>]+>>' Reconcile.md` lists every marker cleanly.
- **`MEMORY.md` ≤150 lines.**

## Reset
`./reset.sh` restores every tracked fixture (incl. seeded `task-6.md`) via `git checkout`, drops
untracked task files via `git clean`, and removes the symlink + `.mockjob/` state.
