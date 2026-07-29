# Mock-memory test cases — 0.5.0 / 0.7.0 / 0.8.0 feature coverage

A persistent, repeatable fixture for the 0.4.0/0.5.0/0.7.0/0.8.0 research-memory / worknote-orchestrate
features (`promote-conclusion`, `set-focus`, Reference-configs mirroring incl. the
`working → failed` regression mirror, template hygiene, read-back verification,
`promotion-drift`, jobs.md status-vocabulary enforcement, config-ref auto-registration,
`working`-verdict evidence gating, and the read-only `query` action — memory QA +
cross-worknote reference; 0.8.0 `<<! ... >>` scoped context blocks). Each case = a fixture built by `setup.sh`, an
**LLM-executed** memory action, and a `assert.sh` post-condition.

The memory "actions" are natural-language instructions the agent performs by following
the dispatch skeleton in `skills/research-memory/SKILL.md`. Only **fixture setup** and
**assertions** are scripted; action execution is agent-driven.

## Execution mode (IMPORTANT)

- Run each action as the **main agent**, or as a subagent that has **pre-approved Edit
  permissions**. Sandboxed subagents cannot write to the scratch store — in the original
  0.4.0 dry-run both dispatch subagents were blocked by sandbox/Edit permissions, so all
  writes had to be main-agent-executed. Do not assume a vanilla `general-purpose` dispatch
  can mutate the fixture.
- **Refusal cases (P3, P4, P5, J1, C5, S2)** expect **no file mutation** plus a refusal
  message that names the violated rule. `assert.sh` enforces byte-identical stores via `diff -r`.
  In each refusal case the agent MUST also write its verbatim (≤3-line) refusal message to
  `$S/refusal.txt` (in `$SCRATCH`, **not** the store, so the byte-identical `diff -r` is
  unaffected); `assert.sh` greps it for the per-case rule keyword so a wrong-reason refusal
  or a crash cannot pass.
- **D1** and **X3** run the read-only `status` invocation, not a memory action.
- **Context cases (X1–X3)** exercise `<<! ... >>` scoped context blocks. Use
  `skills/worknote-orchestrate/scripts/wn_scan.py` (read-only) to resolve spans/chains. Captures
  (`dispatch-2.txt`, `status-output.txt`) land in `$SCRATCH`, **never** in the store.
- **W1** simulates a read-back failure with `chmod 444` on `MEMORY.md`; restore perms after.
- **Query cases (Q1–Q5)** run the **read-only** `query` action. The agent follows the
  "Query dispatch skeleton" in `skills/research-memory/SKILL.md`, then writes the returned
  answer **verbatim** to `$S/answer.txt` (mirrors the `refusal.txt` pattern; lives in `$SCRATCH`,
  **not** the store, so the byte-identical `diff -r` is unaffected) and **touches nothing** in the
  store. `assert.sh` enforces byte-identical stores and greps `answer.txt` for the expected fact,
  evidence pointer, or explicit NOT FOUND. Q3 also asserts the **foreign** store is byte-identical.

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
  > Write your verbatim (≤3-line) refusal message to `$S/refusal.txt`.

- **Expected:** **REFUSE** — the text has no evidence pointer; a promoted conclusion must
  cite its evidence. No file is modified.
- **Assert:** `bash tests/mock-memory/assert.sh P3 "$S"`

## P4 — promote refusal: missing task file

- **Fixture:** `fresh` (only `tasks/task-1.md` exists).
- **Setup:** `bash tests/mock-memory/setup.sh P4 "$S"`
- **Action:**

  > research-memory `promote-conclusion`, id `2`, store `$S/research-memory`. Text:
  > "batch=128 is optimal — job srun-777, /logs/777.txt". Note `tasks/task-2.md` does not
  > exist. Follow the spec. Write your verbatim (≤3-line) refusal message to `$S/refusal.txt`.

- **Expected:** **REFUSE** — `tasks/task-2.md` is missing; a conclusion must trace back to
  a real task file. No file is modified.
- **Assert:** `bash tests/mock-memory/assert.sh P4 "$S"`

## P5 — set-focus refusal: empty text

- **Fixture:** `fresh`.
- **Setup:** `bash tests/mock-memory/setup.sh P5 "$S"`
- **Action:**

  > research-memory `set-focus`, store `$S/research-memory`. Text: (empty). Follow the spec.
  > Write your verbatim (≤3-line) refusal message to `$S/refusal.txt`.

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

  > Note (best-per-family, E4): `baseline-v2` is the only config in its family here, so it is
  > trivially the current family-best — the mirror IS correct. C6 covers the contrasting case where
  > a same-family `working` transition is NOT the family-best and therefore mirrors nothing.

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

  > Note: an `untested → failed` transition mirrors nothing because the config was never a
  > reference (nothing was mirrored into MEMORY.md to update), so MEMORY.md stays
  > byte-identical. This is distinct from C4's `working → failed`, where the OLD status
  > *was* a reference and the mirror line MUST be updated. The 0.5.0 mirror rule keys on
  > **old OR new** status ∈ `working`/`superseded`; `untested → failed` matches neither.

## C4 — update-config-status working → failed (mirror UPDATED on regression)

- **Fixture:** `config-working` (same builder as C2) — `configs.md` `baseline-v2` at
  `working`; MEMORY.md already mirrors it as `(status: working)`.
- **Setup:** `bash tests/mock-memory/setup.sh C4 "$S"`
- **Action:**

  > research-memory `update-config-status`, id `baseline-v2`, status `failed`, store
  > `$S/research-memory`. Evidence: "regression — job srun-700 OOM, /logs/700.txt,
  > 2026-07-10". Flip the `baseline-v2` row in `configs.md` to `failed`. The OLD status was
  > `working`, so baseline-v2 IS mirrored in MEMORY.md "Reference configs" — update that
  > line in place to `(status: failed)` (update-in-place is the spec default; dropping the
  > line is reserved for a supersede chain or an explicit human removal request) so no stale
  > `(status: working)` line survives the regression. Do NOT leave a second baseline-v2 line.

- **Expected:** done — configs row `failed`; exactly ONE `baseline-v2` Reference-configs
  line, now `(status: failed)`; no stale `(status: working)` line.
- **Assert:** `bash tests/mock-memory/assert.sh C4 "$S"`

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

## C5 — update-config-status → working refusal (evidence job failed)

- **Fixture:** `config-evidence-failed` — `configs.md` `baseline-v2` at `untested`;
  `jobs.md` has a `failed` row for job `srun-500` (the run that would be cited as evidence).
- **Setup:** `bash tests/mock-memory/setup.sh C5 "$S"`
- **Action:**

  > research-memory `update-config-status`, id `baseline-v2`, status `working`, store
  > `$S/research-memory`. Evidence: "job srun-500 — reuse path engaged". Note: `jobs.md`
  > records `srun-500` as `failed`. Follow the spec. Write your verbatim (≤3-line) refusal
  > message to `$S/refusal.txt`.

- **Expected:** **REFUSE** — a `working` verdict requires the cited evidence job's latest
  `jobs.md` row to be `finished`, but the cited `srun-500`'s latest row is `failed`; a
  verified sub-effect (reuse engaged) belongs in key-knobs/evidence, not the status. No
  file is modified.
- **Assert:** `bash tests/mock-memory/assert.sh C5 "$S"`

## J1 — add-job refusal: out-of-vocabulary status

- **Fixture:** `fresh`.
- **Setup:** `bash tests/mock-memory/setup.sh J1 "$S"`
- **Action:**

  > research-memory `add-job`, store `$S/research-memory`. Row: timestamp now, job id
  > `srun-810`, purpose "sweep dp=8", config ref `configs.md#baseline-v2`, owner `tab:mock`,
  > status `released`, result ptr `—`. Follow the spec. Write your verbatim (≤3-line) refusal
  > message to `$S/refusal.txt`.

- **Expected:** **REFUSE** — `released` is outside the closed jobs.md vocabulary
  (`submitted/running/finished/failed/cancelled`); name the invented value. No file is modified.
- **Assert:** `bash tests/mock-memory/assert.sh J1 "$S"`

## J2 — add-job with unregistered config ref → auto-add untested configs row

- **Fixture:** `fresh` (pristine `configs.md`, no real config rows).
- **Setup:** `bash tests/mock-memory/setup.sh J2 "$S"`
- **Action:**

  > research-memory `add-job`, store `$S/research-memory`. Row: timestamp now, job id
  > `srun-800`, purpose "reuse test pmt=32", config ref `configs.md#pmt32`, owner `tab:mock`,
  > status `submitted`, result ptr `—`. `pmt32` has NO row in `configs.md`; per the spec, add
  > an `untested` configs.md row for `pmt32` in this SAME dispatch, normalizing the ref to its
  > anchor (id `pmt32`) with evidence citing this job (`srun-800`).

- **Expected:** done — `jobs.md` has the `srun-800` row referencing `configs.md#pmt32`;
  `configs.md` gained exactly one `pmt32` row at `untested`, its evidence citing `srun-800`.
- **Assert:** `bash tests/mock-memory/assert.sh J2 "$S"`

## S1 — set-focus prune: bloated DONE changelog → ≤5 forward-looking bullets

- **Fixture:** `focus-bloated` — MEMORY.md "Current focus" drifted into a 6-bullet
  `DONE 2026-07-14: filled placeholder #N …` changelog.
- **Setup:** `bash tests/mock-memory/setup.sh S1 "$S"`
- **Action** (research-memory `set-focus`):

  > research-memory `set-focus`, store `$S/research-memory`. Rewrite "Current focus" IN PLACE as a
  > FORWARD-LOOKING list (in-progress + immediate next steps), ≤5 bullets, NOT a changelog. New
  > bullets: "profiling tp=16 variant (#17)" and "next: draft the throughput comparison table". Per
  > the spec, DROP the finished `DONE #N` bullets — completed placeholders live in Validated
  > conclusions / jobs.md / task Outcomes, not here. Touch no other section.

- **Expected:** done — Current focus is ≤5 bullets, forward-looking, with no `DONE #N` entries;
  other sections unchanged.
- **Assert:** `bash tests/mock-memory/assert.sh S1 "$S"`

## S2 — set-focus refusal: pure DONE-changelog bullet

- **Fixture:** `fresh`.
- **Setup:** `bash tests/mock-memory/setup.sh S2 "$S"`
- **Action:**

  > research-memory `set-focus`, store `$S/research-memory`. Text: append a per-placeholder bullet
  > "DONE 2026-07-14: filled placeholder #16 — final report assembled" to Current focus. Follow the
  > spec. Write your verbatim (≤3-line) refusal message to `$S/refusal.txt`.

- **Expected:** **REFUSE** — Current focus is forward-looking, not a completion log; a pure `DONE #N`
  changelog bullet does not belong there (record completion in Validated conclusions / jobs.md /
  task Outcome). No file is modified.
- **Assert:** `bash tests/mock-memory/assert.sh S2 "$S"`

## J3 — add-job: released/scancelled pool reservation → `cancelled`

- **Fixture:** `pool-running` — `jobs.md` has `srun-900` as a `running` pool reservation holder.
- **Setup:** `bash tests/mock-memory/setup.sh J3 "$S"`
- **Action:**

  > research-memory `add-job`, store `$S/research-memory`. The `srun-900` pool reservation was
  > scancelled/released. Append its terminal row: timestamp now, job id `srun-900`, purpose "pool
  > reservation (8 nodes)", config ref `configs.md#baseline-v2`, owner `tab:mock`. Per the spec, a
  > released/scancelled pool maps to status **`cancelled`** (NOT `released`) with the release reason
  > in the result ptr (e.g. "scancelled — sweep done").

- **Expected:** done — `jobs.md` gains a `srun-900` row at `cancelled` (release reason in result
  ptr); no `released` status anywhere.
- **Assert:** `bash tests/mock-memory/assert.sh J3 "$S"`

## K1 — add-script: relocate a root helper under `scripts/` + cite it

- **Fixture:** `stray-script` — a reusable helper `collect_tps.py` was created ad hoc at the memory
  ROOT, referenced nowhere (the F3 drift).
- **Setup:** `bash tests/mock-memory/setup.sh K1 "$S"`
- **Action** (research-memory `add-script`):

  > research-memory `add-script`, name `collect_tps.py`, description "extract tok/s from a run log",
  > store `$S/research-memory`. The helper currently sits at the memory root. Per the spec, MOVE it
  > to `scripts/collect_tps.py` AND add its `runbook.md` §Collect citation in the SAME dispatch. The
  > root copy must not survive; the script must not be left uncited.

- **Expected:** done — `scripts/collect_tps.py` exists, no `collect_tps.py` at the root, and
  `runbook.md` §Collect cites it.
- **Assert:** `bash tests/mock-memory/assert.sh K1 "$S"`

## C6 — non-family-best `working` transition → configs.md only (no Reference line)

- **Fixture:** `config-family-best` — `configs.md` has `family-a-best` @ `working` (mirrored in
  MEMORY.md "Reference configs") and `family-a-alt` @ `untested`; `jobs.md` has a `finished`
  `srun-610` for the alt (1180 tok/s, slower than the best).
- **Setup:** `bash tests/mock-memory/setup.sh C6 "$S"`
- **Action:**

  > research-memory `update-config-status`, id `family-a-alt`, status `working`, store
  > `$S/research-memory`. Evidence: "job srun-610 finished, 1180 tok/s, /logs/610.txt". Flip the
  > `family-a-alt` row in `configs.md` to `working`. Note `family-a-alt` is NOT the family best
  > (family-a-best already runs faster). Per the spec, "Reference configs" is a curated best-per-
  > family shortlist, so a non-best `working` transition updates `configs.md` ONLY — do NOT add a
  > `family-a-alt` Reference line; leave MEMORY.md untouched.

- **Expected:** done — `configs.md` `family-a-alt` row is `working`; MEMORY.md byte-identical (no
  new Reference line — the shortlist keeps only the family-best).
- **Assert:** `bash tests/mock-memory/assert.sh C6 "$S"`

## X1 — context hiding: a dispatch carries only its own chain

- **Fixture:** `worknote-context` — `Scratch.md` with a preamble `<<! GLOBAL-CTX-AAA … >>`,
  `## S1` holding `<<! SEC1-CTX-BBB … >>` + `<<#1 …>>`, and `## S2` holding
  `<<! SEC2-CTX-CCC … >>` + `<<#2 …>>`.
- **Setup:** `bash tests/mock-memory/setup.sh X1 "$S"`
- **Action** (build the dispatch prompt for `#2` — **no agent run, no writes**):

  > For `$S/Scratch.md`, resolve the context chain of placeholder `#2` (e.g.
  > `python3 skills/worknote-orchestrate/scripts/wn_scan.py "$S/Scratch.md" --id 2`) and build the
  > Mode A placeholder-agent dispatch prompt for `#2` per the SKILL.md skeleton, including the
  > `Context (inherited, outermost → innermost):` field. Do NOT dispatch it and do NOT write to the
  > worknote. Save the full prompt text to `$S/dispatch-2.txt`.

- **Expected:** the prompt contains `GLOBAL-CTX-AAA` and `SEC2-CTX-CCC` and **not**
  `SEC1-CTX-BBB` (hiding); `Scratch.md` byte-identical.
- **Assert:** `bash tests/mock-memory/assert.sh X1 "$S"`

## X2 — id-stamping never stamps a context block

- **Fixture:** `worknote-context-unstamped` — un-stamped `<<...>>` placeholders interleaved with
  `<<! ... >>` context blocks.
- **Setup:** `bash tests/mock-memory/setup.sh X2 "$S"`
- **Action** (planning-scan id-stamping step):

  > Run the planning scan's id-stamping step on `$S/Scratch.md`: scan for `<<[^<>]+?>>`, partition
  > out every match whose body starts with `!` (context blocks — never stamped, never counted), and
  > stamp each remaining un-stamped placeholder with the next id per the `max`-over-three-sources
  > rule (store `$S/research-memory`). Edit the worknote top-to-bottom. Stamp nothing else.

- **Expected:** the two real placeholders become `<<#1 …>>` / `<<#2 …>>`; both context blocks are
  byte-identical (no `<<!#` anywhere).
- **Assert:** `bash tests/mock-memory/assert.sh X2 "$S"`

## X3 — `context-drift` detection via `status`

- **Fixture:** `worknote-context-drift` — `Scratch.md` has `<<RUNNING#1 …>>` under
  `<<! NEW-CTX-EEE … >>`; `tasks/task-1.md`'s Attempt records `context: OLD-CTX-FFF`.
- **Setup:** `bash tests/mock-memory/setup.sh X3 "$S"`
- **Action** (read-only worknote-orchestrate `status`, mirrors D1):

  > Run `/worknote-orchestrate "$S/Scratch.md" status` — read-only (no writes, no dispatches, no
  > stamping). Resolve each placeholder's `<<! ... >>` chain and compare it against the `context:`
  > line of the latest Attempt in `research-memory/tasks/task-<id>.md`. Save the resulting status
  > table to `$S/status-output.txt`.

  Because the Attempt records `OLD-CTX-FFF` while the resolved chain is `NEW-CTX-EEE`, the table
  must show a `context-drift` row for id 1.

- **Expected:** status table has a `context-drift` row for id 1 (detected, never fixed); store
  byte-identical.
- **Assert:** `bash tests/mock-memory/assert.sh X3 "$S"`

## Q1 — query: how to reproduce the last job

- **Fixture:** `query-repro` — `runbook.md` §Submit has `sbatch --nodes=2 run.sh <config>`;
  `configs.md` has a `pmt-repro` row (key knobs); `jobs.md` has two rows whose **last** (most
  recent) is `srun-950` / `configs.md#pmt-repro` (the earlier is `srun-900` / baseline).
- **Setup:** `bash tests/mock-memory/setup.sh Q1 "$S"`
- **Action** (research-memory `query`, read-only):

  > research-memory `query`, store `$S/research-memory`. Question: "how do I reproduce the last
  > job?" Follow the Query dispatch skeleton: search order `MEMORY.md` → `jobs.md` (the LAST row is
  > the most recent job) → its `config ref` row in `configs.md` (key knobs) → `runbook.md` §Submit
  > (the launch command); assemble a reproduction recipe naming THAT job id, its config, and the
  > submit command, each with an evidence pointer. Do NOT modify any file. Write the returned answer
  > verbatim to `$S/answer.txt`.

- **Expected:** answer names `srun-950` + the submit command `sbatch --nodes=2 run.sh`; it does
  NOT cite `srun-900` as the reproduction target. Store byte-identical.
- **Assert:** `bash tests/mock-memory/assert.sh Q1 "$S"`

## Q2 — query: list all the nsys reports

- **Fixture:** `query-nsys` — `jobs.md` result ptrs include two `.nsys-rep` paths
  (`/logs/prof-a.nsys-rep`, `/logs/prof-b.nsys-rep`) plus one non-nsys ptr (`/logs/plain.txt`);
  `tasks/task-1.md` mentions a third nsys path (`/logs/prof-c.nsys-rep`).
- **Setup:** `bash tests/mock-memory/setup.sh Q2 "$S"`
- **Action:**

  > research-memory `query`, store `$S/research-memory`. Question: "list all the nsys reports."
  > Per the skeleton recipe, scan `jobs.md` result pointers + `tasks/task-*.md` Attempts +
  > `runbook.md` §Collect for `nsys` / `.nsys-rep` paths; list every distinct path with the file
  > it came from. Do NOT list non-nsys pointers. Read-only. Write the answer verbatim to
  > `$S/answer.txt`.

- **Expected:** answer lists all three `.nsys-rep` paths (incl. the one from the task file), never
  `/logs/plain.txt`. Store byte-identical.
- **Assert:** `bash tests/mock-memory/assert.sh Q2 "$S"`

## Q3 — query: cross-worknote foreign reference (deduced memory)

- **Fixture:** `query-foreign` — a sibling worknote `$S/Prod.md` plus its **deduced**
  `$S/Prod.memory/` store, whose `MEMORY.md` "Validated conclusions" holds the answer
  (`PROD-BATCH-512`). The fact lives ONLY in `Prod.memory` (NOT in `Prod.md`), so a correct query
  must search the deduced memory dir first. The local `$S/research-memory` store is fresh.
- **Setup:** `bash tests/mock-memory/setup.sh Q3 "$S"`
- **Action:**

  > research-memory `query "$S/Prod.md" "what production batch size is validated?"`. This is a
  > FOREIGN reference: deduce the memory dir as `$S/Prod.memory/` (same directory, `<Base>.memory/`)
  > and search it FIRST. Answer with the fact + an evidence pointer into `Prod.memory/`. Do NOT
  > write into the foreign store or the local store. Write the answer verbatim to `$S/answer.txt`.

- **Expected:** answer carries `PROD-BATCH-512` + an evidence pointer into `Prod.memory/`. Both the
  local store AND the foreign `Prod.memory` are byte-identical.
- **Assert:** `bash tests/mock-memory/assert.sh Q3 "$S"`

## Q4 — query: worknote-markdown fallback (no deduced memory)

- **Fixture:** `query-fallback` — a sibling worknote `$S/Notes.md` whose fact
  (`NOTES-ONLY-XYZ`, under `## Deploy`) lives ONLY in the markdown; there is **no** `Notes.memory/`
  beside it, so a query must fall back to a bounded grep of `Notes.md`.
- **Setup:** `bash tests/mock-memory/setup.sh Q4 "$S"`
- **Action:**

  > research-memory `query "$S/Notes.md" "what is the deploy endpoint token?"`. Deduce
  > `$S/Notes.memory/` — it does NOT exist, so fall back to a bounded grep of `Notes.md` itself.
  > Answer with the fact + a pointer to `Notes.md` (cite the §section or line). Read-only. Write the
  > answer verbatim to `$S/answer.txt`.

- **Expected:** answer carries `NOTES-ONLY-XYZ` + a pointer to `Notes.md`. Local store
  byte-identical.
- **Assert:** `bash tests/mock-memory/assert.sh Q4 "$S"`

## Q5 — query miss: explicit NOT FOUND (no invention)

- **Fixture:** `query-miss` — a pristine store with nothing about `tp=64`.
- **Setup:** `bash tests/mock-memory/setup.sh Q5 "$S"`
- **Action:**

  > research-memory `query`, store `$S/research-memory`. Question: "how many tok/s did the tp=64
  > sweep reach?" Search per the skeleton. The store has no such record — per the spec return the
  > explicit `NOT FOUND in <what was searched>` line; NEVER guess or invent a throughput number.
  > Read-only. Write the answer verbatim to `$S/answer.txt`.

- **Expected:** answer is an explicit NOT FOUND / no-record miss; it invents no `tok/s` value.
  Store byte-identical.
- **Assert:** `bash tests/mock-memory/assert.sh Q5 "$S"`

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
| C4 | `working→failed` regression — mirror UPDATED (no stale `working` line) |
| C5 | `→working` refusal — cited evidence job is `failed` in jobs.md |
| C6 | non-family-best `working` → configs.md only, no Reference line (best-per-family shortlist) |
| J1 | `add-job` refusal — out-of-vocabulary status (`released`) |
| J2 | `add-job` unregistered config ref → auto-add `untested` configs row |
| J3 | `add-job` released/scancelled pool reservation → `cancelled` (positive mapping) |
| K1 | `add-script` — relocate root helper under `scripts/` + cite in runbook §Collect |
| S1 | `set-focus` prune — bloated DONE changelog → ≤5 forward-looking bullets |
| S2 | `set-focus` refusal — pure DONE-changelog bullet |
| L1 | ≤150-line curation on promote (pointers preserved) |
| D1 | `promotion-drift` detection by `status` (read-only) |
| W1 | read-back failure → `promoted: FAILED` (Outcome write-once) |
| X1 | `<<! ... >>` context hiding — a dispatch carries only its own resolved chain |
| X2 | id-stamping partitions out context blocks (never stamped, never counted) |
| X3 | `context-drift` detection by `status` (read-only) |
| Q1 | `query` — reproduce the last job (jobs.md EOF → configs key knobs → runbook §Submit) |
| Q2 | `query` — list all nsys reports (jobs.md ptrs + task Attempts; excludes non-nsys) |
| Q3 | `query <worknote>` — foreign reference via deduced `<Base>.memory/` (read-only) |
| Q4 | `query <worknote>` — worknote-markdown fallback when no `.memory/` exists |
| Q5 | `query` miss — explicit NOT FOUND, no invented specifics |
