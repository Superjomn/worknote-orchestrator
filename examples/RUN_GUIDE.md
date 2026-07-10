# RUN_GUIDE — how to run the mock test worknotes

Two ways to exercise every scenario: **agent-driven end-to-end** (a Claude session runs
`/worknote-orchestrate`) and **manual by-hand** (you drive `mockjob` + hand-edit markers yourself).
Both use the same fixtures and the same `bin/mockjob` scheduler. No GPU.

## Running on sonnet (cost)

The `worknote-orchestrate` and `research-memory` skills do not hardcode a model, so you choose it
at the session level:

1. **Start the coordinator session on sonnet**, then invoke `/worknote-orchestrate <worknote>`.
2. **Tell the coordinator, in its first prompt, to dispatch every subagent on sonnet** — both the
   Mode A placeholder-agents and the research-memory write subagents. For example, append to your
   invocation:
   > "Run every dispatched general-purpose Agent (placeholder-agents and research-memory
   > subagents) with `model: sonnet`."

This keeps the whole fan-out cheap; the mock jobs finish in milliseconds so wall-clock is trivial.

## Common setup

```bash
cd examples/scenario-A-fanout   # or -B/-C/-D
./setup.sh                      # creates the workdir research-memory symlink(s), registers them in
                                # git info/exclude, resets/seeds the .mockjob state. Prints abs paths.
```

The store is **pre-seeded** — do NOT run `research-memory init`. `setup.sh` prints the absolute
worknote path to hand to `/worknote-orchestrate`.

After a run, `./reset.sh` restores the committed seed and removes the symlink + `.mockjob/` state.

---

## Scenario A — fan-out + one blocker (the vertical slice)

```bash
cd examples/scenario-A-fanout && ./setup.sh
```
Agent session (sonnet):
1. `/worknote-orchestrate <abs>/Fanout.md`
2. Approve the plan. Expect: `#1` classified fill-from-data (answered from `MEMORY.md`), `#2`/`#3`/`#4`
   needs-work Mode A. Ids stamped `#1`..`#4`.
3. The coordinator fans out dp=2/dp=4 (plan `fast-ok` → finished) and dp=8 (plan `fail` → the agent
   records a blocker and flips `#4` to `BLOCKED`).
4. Answer the ONE batched `AskUserQuestion`: **`skip dp=8, note OOM`**.
5. Coordinator writes the answer, re-dispatches `#4`, which records the skip decision.
6. Compare `Fanout.md` + `Fanout.memory/` against `EXPECTED.md`.
```bash
./reset.sh
```

## Scenario B — reconciliation (two passes)

```bash
cd examples/scenario-B-reconcile && ./setup.sh
```
**Pass 1 — status (read-only):**
1. Snapshot for the byte-diff check: `git stash` is not needed; instead `cp -r` the worknote +
   memory somewhere, or just note `git status --porcelain` is clean.
2. `/worknote-orchestrate <abs>/Reconcile.md status`
3. Verify the printed reconciliation table matches `EXPECTED.md` (running, stale-claim ×2, blocked,
   blocked+answered, orphaned-job, done-but-unwritten).
4. **Assert nothing was written**: `git status --porcelain` still clean; the pre-copied snapshot
   `diff`s empty. `status` never writes/stamps/dispatches.

**Pass 2 — planning scan:**
5. `/worknote-orchestrate <abs>/Reconcile.md`, approve the plan.
6. Expect: `#5` (blocked+answered) re-activated → submits mock-0010 (`fast-ok`) → finished → final
   content; `#2`/`#3` treated as resumable stale claims; `#4` left untouched (awaiting input) unless
   you answer it in the batched round.
7. Compare against `EXPECTED.md` (next stamped id would be `#7`).
```bash
./reset.sh
```

## Scenario C — directives (two workdirs)

```bash
cd examples/scenario-C-directives && ./setup.sh   # prints the abs base for @dir: resolution
```
1. `/worknote-orchestrate <abs>/Directives.md`, approve.
2. Expect: `#1` filled from memory; `#2` routed into `workdir-alpha`, `#3` into `workdir-beta`,
   `#4` (`@run` alone) in the default workdir. All jobs `fast-ok`.
3. Confirm `tasks/task-2.md` / `task-3.md` Briefs name the alpha/beta workdirs; all rows land in the
   single shared `Directives.memory/`.
```bash
./reset.sh
```

## Scenario D — human edits mid-flight (two phases)

```bash
cd examples/scenario-D-human-edit && ./setup.sh
```
1. **Phase 1:** `/worknote-orchestrate <abs>/HumanEdit.md`. Three markers are on live `hang-running`
   jobs; the coordinator reports them running.
2. **Between phases:** `./mutate.sh` (or edit `HumanEdit.md` by hand as its output documents):
   delete `#1` (cancel), reword `#2`'s `task:` to `sweep dp=4 with bs=128` (supersede), delete `#3`
   (lost-result, on an already-finished job).
3. **Phase 2:** `/worknote-orchestrate <abs>/HumanEdit.md`, approve. Expect: `#1` → `cancelled` row,
   no marker re-inserted, optional kill offered in the batched round (never silent); `#2` superseded
   → old dispatch cancelled + re-dispatched with the new text; `#3` recorded fully in memory with the
   run reporting `#3 done (worknote not updated: marker missing)`.
4. Compare against `EXPECTED.md`.
```bash
./reset.sh
```

---

## Manual (by-hand) walk — no agent required

The seeded runbooks make every command literal. From inside a scenario `workdir/` after `setup.sh`:

**A pending → running → done point:**
```bash
cd examples/scenario-A-fanout/workdir
JOB=$(../../bin/mockjob submit --purpose "sweep dp=2, collect throughput" --plan fast-ok)
echo "$JOB"                        # e.g. mock-0001
../../bin/mockjob status "$JOB"    # finished
../../bin/mockjob collect "$JOB"   # throughput=1234.5 tok/s
```
Then hand-edit the worknote marker through the state machine:
`<<#2 ...>>` → `<<RUNNING#2 owner=tab:me job=mock-0001 since=<date> task: sweep dp=2>>` → final content.

**A running → blocked → answered → running → done point (the dp=8 failure):**
```bash
JOB=$(../../bin/mockjob submit --purpose "sweep dp=8, collect throughput" --plan fail)
../../bin/mockjob status "$JOB"    # failed
../../bin/mockjob collect "$JOB"   # OOM at dp=8   (exit 5)
```
Flip the marker to `<<BLOCKED#4 ... Q: OOM at dp=8 — reduce or skip?>>`, append an answer
`A: skip, note OOM`, then re-run (or by hand) resolve it to the skip decision.

Record every job/config/blocker via the `research-memory` actions (or, by hand, follow the exact
schemas in `<Name>.memory/`). The `.mockjob` state persists across commands within a scenario, so a
later `status <id>` resolves a job an earlier command submitted — exactly the cross-session contract
the real runbook relies on.
