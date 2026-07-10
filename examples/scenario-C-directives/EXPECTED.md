# EXPECTED — scenario-C-directives

Stresses: **hint directives** — `@dir:<workdir>` routing to two different workdirs, `@memory`
(fill-from-data), and bare `@run` (needs-work in the default/invocation workdir). All jobs use
`plan=fast-ok`; no GPU. All three workdirs symlink `./research-memory` → the SAME
`Directives.memory/` store (fixed-path sharing), so every job row lands in that one store.

Seeded start: 4 un-stamped placeholders, `configs.md` with `baseline=working` (best validated
throughput) + `bs32/bs64/bs128=untested`, empty `jobs.md`/`blockers.md`, one Validated-conclusion
for the baseline in `MEMORY.md`.

Assert **effects**, not exact prose.

## 1. Worknote (`Directives.md`)

- **No `<<...>>` placeholders remain.** Check: `grep -c '<<' Directives.md` → `0`.
- **`#1 @memory` (fill-from-data):** the Setup section quotes the best validated throughput
  **1400.0 tok/s** in prose, with **no marker** (never dispatched). Check: `grep -F '1400' Directives.md`.
- **`#2 / #3 / #4` (needs-work):** each Results bullet ends in a concrete latency/throughput
  number from `collect`; markers gone.
- **Output discipline:** no `mockjob`/command lines and no raw `mock-####` job ids leak into the
  worknote. Check: `grep -E 'mock-[0-9]|mockjob|--plan|submit ' Directives.md` → no matches.
- Conclusion section written.

## 2. Directive routing (the core assertion)

- **`#2` ran in `workdir-alpha`:** `tasks/task-2.md` Brief `workdir:` ends in `.../workdir-alpha`.
  Check: `grep -A2 'Brief' Directives.memory/tasks/task-2.md | grep workdir-alpha`.
- **`#3` ran in `workdir-beta`:** `tasks/task-3.md` Brief `workdir:` ends in `.../workdir-beta`.
- **`#4` (bare `@run`) ran in the default invocation workdir:** `tasks/task-4.md` Brief `workdir:`
  is NOT `workdir-alpha` or `workdir-beta` (it is the plain `workdir`, or wherever the coordinator
  invoked). Check: `grep workdir Directives.memory/tasks/task-4.md` shows neither alpha nor beta.

## 3. Memory (single shared store)

- `jobs.md`: **≥3 appended rows** (bs32, bs64, bs128), all 7 columns filled, `config ref` →
  `configs.md#bs32|bs64|bs128`. Header + empty seed table byte-identical above the first append.
  All rows are in the ONE `Directives.memory/jobs.md` (proving fixed-path sharing).
- `configs.md`: `bs32`, `bs64`, `bs128` → `working` with evidence (their `mock-*` ids); `baseline`
  row unchanged.
- `blockers.md`: unchanged (no blockers in this scenario).
- `tasks/task-2.md`, `task-3.md`, `task-4.md` each have Attempt 1 + Outcome filled.
- `MEMORY.md` ≤150 lines with a Validated-conclusions bullet per validated bs point, each with a
  `→ tasks/task-<id>.md` pointer.

## 4. Invariants
- Placeholders were stamped `#1`..`#4` at plan approval; next free id (over marker heads +
  `tasks/task-*.md` filenames + blocker ids) would be `#5`.
- Markers stayed valid `<<...>>` (no nested `<`/`>`).
- `MEMORY.md` ≤150 lines. Check: `wc -l Directives.memory/MEMORY.md` ≤ 150.

## Reset
`./reset.sh` restores every tracked fixture and removes all three symlinks + `.mockjob/` state.
