# EXPECTED — scenario-A-fanout

Stresses: **classification** (fill-from-data vs needs-work) + **Mode A parallel fan-out** +
**one BLOCKED→answered cycle**. All jobs run against `mockjob`; no GPU.

Seeded start: 4 placeholders (1 `@memory`, 3 `@run`), `configs.md` has `baseline=working` +
`dp2/dp4/dp8=untested` (dp8 carries `plan=fail`), empty `jobs.md`/`blockers.md` ledgers, one
Validated-conclusion for the baseline in `MEMORY.md`.

Post-run assertions below are grep/`wc`/`diff`-checkable where noted. Model prose is best-effort —
assert **effects**, not exact wording.

## 1. Worknote (`Fanout.md`)

- **No `<<...>>` placeholders remain.** Check: `grep -c '<<' Fanout.md` → `0`.
- **`#1 @memory` (fill-from-data):** the Setup section contains prose naming the baseline config
  and its throughput **1000.0 tok/s**, with **no marker** (it was never dispatched). Check:
  `grep -F '1000' Fanout.md`.
- **`#2 dp=2` and `#3 dp=4` (needs-work happy path):** each bullet ends in a concrete throughput
  number from `collect` (the `mock-*` metric). Markers are gone.
- **`#4 dp=8` (needs-work → BLOCKED → answered `skip dp=8, note OOM`):** the dp=8 bullet reads as
  **skipped due to OOM** (decision content), not a number. Marker is gone.
- **Output discipline:** no `mockjob`/`srun`/command lines and **no raw `mock-####` job ids** leak
  into the worknote. Check: `grep -E 'mock-[0-9]|mockjob|--plan|submit ' Fanout.md` → no matches.
- The Conclusion section is written (scaling summary citing the collected points).

## 2. Memory

### `jobs.md` (append-only, 7 columns)
- At least **3 appended rows** (dp2, dp4, dp8 submits; status-change rows optional but must be
  appends). Each row fills all 7 columns; `config ref` points at `configs.md#dp2|dp4|dp8`.
- Header block and the (empty) seed table are byte-identical above the first appended row.

### `configs.md` (mutable)
- `dp2` → `working` with an evidence pointer (its `mock-*` id).
- `dp4` → `working` with an evidence pointer.
- `dp8` → `failed` with an evidence pointer (the failed `mock-*` id).
- `baseline` row unchanged.

### `blockers.md` (append-only, `Answer:` mutable)
- Exactly **one** `### BLOCKED#4` entry, every field filled (evidence = the failed dp8 job id),
  and its `Answer:` now contains the human guidance (`skip`, `OOM`). Check:
  `grep -A1 'BLOCKED#4' blockers.md` and confirm a non-empty `Answer:`.

### `tasks/task-*.md`
- `task-2.md`, `task-3.md`, `task-4.md` exist. `task-4.md` has **≥2 Attempts** (Attempt 1 =
  blocked on OOM; Attempt 2 = re-dispatch with the answer → skipped), Attempt 1 not rewritten,
  and **Outcome filled**.

### `MEMORY.md` (≤150 lines)
- Still ≤150 lines. Check: `wc -l MEMORY.md` ≤ 150.
- A "Validated conclusions" bullet per validated result (dp2, dp4), each with a
  `→ tasks/task-<id>.md` pointer. dp8's skip may be noted but is not a validated throughput.

## 3. Invariants
- **id monotonicity:** placeholders were stamped `#1`..`#4` at plan approval; next free id (over
  marker heads + `tasks/task-*.md` filenames + blocker ids) would be `#5`.
- **markers stayed valid `<<...>>`** throughout (no nested `<`/`>`).
- **`MEMORY.md` ≤150 lines.**

## Reset
`./reset.sh` restores every tracked fixture to its committed seed and removes the symlink +
`.mockjob/` state.
