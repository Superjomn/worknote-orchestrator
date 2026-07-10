# EXPECTED — scenario-D-human-edit

Stresses **human-edit resilience**: a mid-flight cancel, a supersede, and a lost-result — driven
by editing the worknote between two runs. Two phases with `./mutate.sh` (or the documented manual
edits) in between.

Seeded start: 3 pre-stamped `RUNNING` markers #1–#3 on live jobs (mock-0001/0002 = `hang-running`
→ stay running; mock-0003 = `fast-ok` → already finished + recorded in `task-3.md` / jobs.md).

---

## Phase 1 — `/worknote-orchestrate <abs>/HumanEdit.md`

All three markers point at live ledger jobs, so there is nothing to cancel/supersede yet.

- The coordinator reports #1 and #2 as **running** (mock-0001/0002 resolve `running`). #3's job
  mock-0003 resolves `finished`, so #3 may be reconciled to final dp=8 content OR left as-is; either
  is acceptable in phase 1 since the point of the scenario is the phase-2 edits.
- **Assert:** the three markers are still present and valid `<<...>>`; `jobs.md` seed rows are
  byte-identical (only appends allowed); no blocker created.

## Between phases — `./mutate.sh`

Applies the human edit to `HumanEdit.md`:

1. **Cancel** — deletes the `<<RUNNING#1 ...>>` bullet line (marker gone).
2. **Supersede** — rewrites #2's `task: sweep dp=4` → `task: sweep dp=4 with bs=128`.
3. **Lost-result** — deletes the `<<RUNNING#3 ...>>` bullet line (job mock-0003 already finished).

Manual equivalent: open `HumanEdit.md`, delete the dp=2 and dp=8 bullets, and append ` with bs=128`
to #2's `task:` text (keeping it a valid `<<RUNNING#2 ...>>`).

---

## Phase 2 — `/worknote-orchestrate <abs>/HumanEdit.md`  (planning scan)

The scan reconciles markers against the ledger and applies the drift writes:

### #1 — CANCELLED (marker deleted)
- mock-0001 is ledger-`running` but its marker vanished → **cancel**.
- **Assert:** the `#1` marker is absent and **NOT re-inserted**; `jobs.md` gets an **appended**
  `cancelled` row for `mock-0001` (7 columns). Check: `grep 'mock-0001' jobs.md | grep cancelled`.
- The coordinator OFFERS an optional kill of mock-0001 in the batched `AskUserQuestion` round but
  **never silently auto-kills**. (No blocker/kill row appears without the human being asked.)

### #2 — SUPERSEDED (task: drift)
- #2's `task:` now reads `sweep dp=4 with bs=128`, which drifts from the `configs.md#dp4` /
  `mock-0002` dispatch in `jobs.md` → **supersede**.
- **Assert:** an **appended** `cancelled`/superseded row for the old `mock-0002` dispatch, AND #2 is
  **re-dispatched** with the new text → a fresh Attempt (`### Attempt 2`) in `tasks/task-2.md` and a
  new job (`mock-0004`, the next seq id). #2's marker returns to `RUNNING#2 job=mock-0004` (running,
  since dp4 is `hang-running`) or resolves once collected.

### #3 — LOST-RESULT (marker deleted post-finish)
- mock-0003 already `finished` (task-3.md Outcome filled). Its marker was deleted, so a re-dispatch
  or write-back agent re-greps, finds **no marker**, and — results never lost — records everything in
  memory (task-3.md already holds the Outcome; `add-job` result ptr already present) and the run
  returns **`#3 done (worknote not updated: marker missing)`**, surfaced by the coordinator in its
  summary. **Assert:** that status line appears; `task-3.md` Outcome is unchanged (write-once); no
  `#3` marker is re-inserted into the worknote.

### Memory invariants after Phase 2
- `jobs.md`: 4 seed rows **byte-identical**; only **appended** rows added (the `cancelled` row for
  mock-0001, the superseded row + mock-0004 rows for #2). Every row 7 columns.
- `configs.md`: dp4 may go `superseded`/`untested`→re-run; dp8 stays `working`.
- `MEMORY.md`: **≤150 lines**.

---

## Invariants (all phases)
- **Markers stayed valid `<<...>>`** (no nested `<`/`>`). Check: `grep -oE '<<[^<>]+>>' HumanEdit.md`.
- **id monotonicity:** max marker-head id was #3, plus `tasks/task-3.md` → next placeholder id
  would be **#4**. (Job seq: max seeded mock-0003 → next submit **mock-0004**.)
- **`MEMORY.md` ≤150 lines.**
- **No result lost:** dp=8's 1250.0 tok/s remains recoverable from `task-3.md` + `jobs.md` even
  though its marker was deleted.

## Reset
`./reset.sh` restores every tracked fixture (worknote's 3 original markers, seeded `task-3.md`) via
`git checkout`, drops untracked task files, and removes the symlink + `.mockjob/` state.
