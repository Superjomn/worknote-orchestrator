# Mock-memory test cases — 0.4.0 feature coverage

A persistent, repeatable fixture for the 0.4.0 research-memory / worknote-orchestrate
features (`promote-conclusion`, `set-focus`, Reference-configs mirroring, template
hygiene, read-back verification, `promotion-drift`). Each case = a fixture built by
`setup.sh`, an **LLM-executed** memory action, and a `assert.sh` post-condition.

The memory "actions" are natural-language instructions the agent performs by following
the dispatch skeleton in `skills/research-memory/SKILL.md`. Only **fixture setup** and
**assertions** are scripted; action execution is agent-driven.

## Execution mode (IMPORTANT)

- Run each action as the **main agent**, or as a subagent that has **pre-approved Edit
  permissions**. Sandboxed subagents cannot write to the scratch store — in the original
  0.4.0 dry-run both dispatch subagents were blocked by sandbox/Edit permissions, so all
  writes had to be main-agent-executed. Do not assume a vanilla `general-purpose` dispatch
  can mutate the fixture.
- **Refusal cases (P3, P4, P5)** expect **no file mutation** plus a refusal message that
  names the violated rule. `assert.sh` enforces byte-identical stores via `diff -r`.
- **D1** runs the read-only `status` invocation, not a memory action.
- **W1** simulates a read-back failure with `chmod 444` on `MEMORY.md`; restore perms after.

## Scratch directory

Use a scratch dir **outside the repo** (or anywhere git does not track) so `git status`
stays clean outside `tests/`. Examples below use `$S`:

```bash
S=$(mktemp -d)                 # e.g. /tmp/tmp.XXXX
cd <worktree-root>             # so the relative script paths resolve
```

Every case: `bash tests/mock-memory/setup.sh <CASE> "$S"` → run the action → `bash tests/mock-memory/assert.sh <CASE> "$S"`.
The memory store is `$S/research-memory/` (fixed relative path the skill expects).

---

## P1 — promote-conclusion happy path

- **Fixture:** `fresh` — pristine store + `tasks/task-1.md`.
- **Setup:** `bash tests/mock-memory/setup.sh P1 "$S"`
- **Action** (research-memory `promote-conclusion`):

  > Maintain the shared research-memory store at `$S/research-memory`. Action:
  > `promote-conclusion`, id `1`. Target file: `MEMORY.md`. Text: "tp=8 sustains 1420 tok/s,
  > 12% over tp=4 — job srun-901, /logs/901.txt". Append ONE bullet under
  > "Validated conclusions" ending with the timestamp (`date '+%Y-%m-%d %H:%M'`) and
  > `→ tasks/task-1.md`. Apply the template-hygiene rule: delete the italic `_( … )_`
  > example bullet in that section as part of the same edit. Keep MEMORY.md ≤150 lines.

- **Expected:** done — one new bullet; template example gone.
- **Assert:** `bash tests/mock-memory/assert.sh P1 "$S"`

## P2 — duplicate promotion updates in place

- **Fixture:** `promoted` — store already has a `→ tasks/task-1.md` bullet ("1000 tok/s").
- **Setup:** `bash tests/mock-memory/setup.sh P2 "$S"`
- **Action:**

  > research-memory `promote-conclusion`, id `1`, store `$S/research-memory`. Text:
  > "revised: tp=8 sustains UPDATED-1500tok tok/s — job srun-950, /logs/950.txt". A
  > Validated-conclusions bullet ALREADY points at `tasks/task-1.md`; per the spec, UPDATE
  > that bullet in place (do NOT append a second). End with timestamp + `→ tasks/task-1.md`.

- **Expected:** done — still exactly one task-1 bullet, now the revised text.
- **Assert:** `bash tests/mock-memory/assert.sh P2 "$S"`

## P3 — promote refusal: no evidence pointer

- **Fixture:** `fresh`.
- **Setup:** `bash tests/mock-memory/setup.sh P3 "$S"`
- **Action:**

  > research-memory `promote-conclusion`, id `1`, store `$S/research-memory`. Text:
  > "tp=8 is faster than tp=4" (no job id / log path / dashboard URL). Follow the spec.

- **Expected:** **REFUSE** — the text has no evidence pointer; a promoted conclusion must
  cite its evidence. No file is modified.
- **Assert:** `bash tests/mock-memory/assert.sh P3 "$S"`

## P4 — promote refusal: missing task file

- **Fixture:** `fresh` (only `tasks/task-1.md` exists).
- **Setup:** `bash tests/mock-memory/setup.sh P4 "$S"`
- **Action:**

  > research-memory `promote-conclusion`, id `2`, store `$S/research-memory`. Text:
  > "batch=128 is optimal — job srun-777, /logs/777.txt". Note `tasks/task-2.md` does not
  > exist. Follow the spec.

- **Expected:** **REFUSE** — `tasks/task-2.md` is missing; a conclusion must trace back to
  a real task file. No file is modified.
- **Assert:** `bash tests/mock-memory/assert.sh P4 "$S"`

## P5 — set-focus refusal: empty text

- **Fixture:** `fresh`.
- **Setup:** `bash tests/mock-memory/setup.sh P5 "$S"`
- **Action:**

  > research-memory `set-focus`, store `$S/research-memory`. Text: (empty). Follow the spec.

- **Expected:** **REFUSE** — empty focus text. No file is modified.
- **Assert:** `bash tests/mock-memory/assert.sh P5 "$S"`

## C1 — update-config-status untested → working (mirror + hygiene)

- **Fixture:** `config-untested` — `configs.md` has the template example row AND a real
  `baseline-v2` row at `untested`. The example row was deliberately left in place (manual
  seeding bypassed hygiene); this real write must clean it up.
- **Setup:** `bash tests/mock-memory/setup.sh C1 "$S"`
- **Action:**

  > research-memory `update-config-status`, id `baseline-v2`, status `working`, store
  > `$S/research-memory`. Evidence: "job srun-500, verified, 2026-07-05". Flip the
  > `baseline-v2` row in `configs.md` to `working`. Apply template-hygiene: delete the
  > italic `_( … )_` example row in the configs table as part of this edit. Because the new
  > status is `working`, ALSO mirror the pointer in MEMORY.md "Reference configs" — add
  > `baseline-v2 → configs.md#baseline-v2 (status: working)` and delete that section's
  > italic example line.

- **Expected:** done — configs row `working`; MEMORY.md mirror added; both template
  examples gone.
- **Assert:** `bash tests/mock-memory/assert.sh C1 "$S"`

## C2 — update-config-status working → superseded (mirror REPLACE)

- **Fixture:** `config-working` — `configs.md` `baseline-v2` at `working`; MEMORY.md
  already mirrors it as `(status: working)`.
- **Setup:** `bash tests/mock-memory/setup.sh C2 "$S"`
- **Action:**

  > research-memory `update-config-status`, id `baseline-v2`, status `superseded`, store
  > `$S/research-memory`. Evidence: "superseded by baseline-v3 — job srun-620, 2026-07-08".
  > Flip the `baseline-v2` row in `configs.md` to `superseded`. Because the new status is
  > `superseded`, mirror in MEMORY.md "Reference configs" by REPLACING the existing
  > `baseline-v2` line to `(status: superseded)` — do NOT add a second line.

- **Expected:** done — exactly ONE `baseline-v2` Reference-configs line, now `(status:
  superseded)`.
- **Assert:** `bash tests/mock-memory/assert.sh C2 "$S"`

## C3 — update-config-status untested → failed (NO mirror)

- **Fixture:** `config-untested` (same builder as C1).
- **Setup:** `bash tests/mock-memory/setup.sh C3 "$S"`
- **Action:**

  > research-memory `update-config-status`, id `baseline-v2`, status `failed`, store
  > `$S/research-memory`. Evidence: "job srun-510 OOM, /logs/510.txt, 2026-07-06". Flip the
  > `baseline-v2` row in `configs.md` to `failed`. A `→ failed` transition does NOT mirror
  > into MEMORY.md — leave MEMORY.md untouched.

- **Expected:** done — configs row `failed`; MEMORY.md byte-identical to the fixture.
- **Assert:** `bash tests/mock-memory/assert.sh C3 "$S"`

  > Note: C3 asserts the **current** spec (MEMORY.md untouched on `→ failed`). If a later
  > review round changes that behavior, update this case.

## L1 — promote under the 150-line cap (curation)

- **Fixture:** `near-cap` — MEMORY.md is exactly 150 lines of synthetic promoted bullets;
  `tasks/task-90.md` exists.
- **Setup:** `bash tests/mock-memory/setup.sh L1 "$S"`
- **Action:**

  > research-memory `promote-conclusion`, id `90`, store `$S/research-memory`. Text:
  > "final: pipeline reaches 2.1x speedup — job srun-990, /logs/990.txt". MEMORY.md is at
  > the 150-line cap: to stay ≤150 you MUST curate/compress the OLDEST bullets, but NEVER
  > drop any `→ tasks/task-*.md` pointer. End with timestamp + `→ tasks/task-90.md`.

- **Expected:** done — MEMORY.md ≤150 lines; new bullet present; every prior pointer kept.
- **Assert:** `bash tests/mock-memory/assert.sh L1 "$S"`

## D1 — promotion-drift detection via `status`

- **Fixture:** `drifted` — `tasks/task-2.md` Outcome claims `promoted: MEMORY.md bullet`
  but MEMORY.md has no bullet pointing at it; plus a minimal `Scratch.md` worknote.
- **Setup:** `bash tests/mock-memory/setup.sh D1 "$S"`
- **Action** (read-only worknote-orchestrate `status`):

  > Run `/worknote-orchestrate "$S/Scratch.md" status` — a read-only dashboard scan (no
  > writes, no dispatches). Cross-check `research-memory/tasks/*.md` Outcomes against
  > MEMORY.md "Validated conclusions". Save the resulting status table to
  > `$S/status-output.txt`.

  Because `tasks/task-2.md` claims a promotion MEMORY.md does not carry, the table must
  show a `promotion-drift` row for id 2.

- **Expected:** status table has a `promotion-drift` row for id 2 (detected, never fixed).
- **Assert:** `bash tests/mock-memory/assert.sh D1 "$S"`

## W1 — read-back failure → `promoted: FAILED`

- **Fixture:** `worknote` — fresh store + `tasks/task-1.md` + `Scratch.md` with a
  `<<RUNNING#1 ...>>` marker.
- **Setup:** `bash tests/mock-memory/setup.sh W1 "$S"`
- **Action** (Mode B completion with a forced read-back failure):

  1. `chmod 444 "$S/research-memory/MEMORY.md"` (simulate an un-writable MEMORY.md).
  2. research-memory `promote-conclusion`, id `1`, text "tp=8 wins — job srun-901,
     /logs/901.txt". The Edit to MEMORY.md will fail (read-only).
  3. Per the Mode B read-back protocol: bounded-grep MEMORY.md for `tasks/task-1.md` under
     "Validated conclusions". The read-back FAILS. Retry `promote-conclusion` once; it fails
     again. Then write `promoted: FAILED (MEMORY.md read-only)` into the `## Outcome` section
     of `tasks/task-1.md` (fill the Outcome exactly once) so the drift stays visible.
  4. `chmod 644 "$S/research-memory/MEMORY.md"` to restore perms.

- **Expected:** `tasks/task-1.md` Outcome has a single `promoted: FAILED ...` line.
- **Assert:** `bash tests/mock-memory/assert.sh W1 "$S"`

---

## Coverage map

| Case | Feature under test |
|---|---|
| P1 | `promote-conclusion` happy path (evidence + timestamp + ptr) + template hygiene |
| P2 | duplicate promotion → update in place (no duplicate bullet) |
| P3 | promote refusal — no evidence pointer |
| P4 | promote refusal — missing `tasks/task-<id>.md` |
| P5 | `set-focus` refusal — empty text |
| C1 | `untested→working` mirror + configs/Reference template hygiene |
| C2 | `working→superseded` mirror REPLACE (not duplicate) |
| C3 | `untested→failed` — no mirror, MEMORY.md untouched |
| L1 | ≤150-line curation on promote (pointers preserved) |
| D1 | `promotion-drift` detection by `status` (read-only) |
| W1 | read-back failure → `promoted: FAILED` (Outcome write-once) |
