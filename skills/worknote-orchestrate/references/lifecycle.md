# Task lifecycle and recovery

Use [research-memory actions](../../research-memory/references/actions.md) for every memory change. The scanner and memory are complementary: scanner output describes current worknote text; the ledger records observed job state; task records preserve dispatch intent and results.

## Claims and execution

A pending marker is `<<#N task text>>`. Claim it as `<<RUNNING#N owner=agent job=pending since=<timestamp> task: ...>>` or `owner=tab:<name>` for Mode B. Keep timestamps and owner tokens whitespace-free in marker fields. Blockers use `<<BLOCKED#N owner=... since=... task: ... Q: ... A: ...>>`; no field body may introduce nested angle brackets.

Before claiming, reserve the task record and resolve its context. Append a fresh Attempt containing task text, context, owner, and start timestamp. Record the expected Attempt number in the worker dispatch. Serialize claims and verify the marker before starting work; a failed claim leaves a recoverable Attempt with no submitted job, not permission to proceed.

Do not dispatch over a live owner. Takeover requires explicit user selection or an agreed handoff. Invalidate the old dispatch, close its active Attempt with the reason (or record invalidation in Working notes if it is already closed), open a new Attempt, then replace its claim. If no agent is known to be active, reconcile job state before deciding whether to resume monitoring or run new work. A job=pending marker's age alone does not prove its owner dead; without a known submission-time bound or owner state, report uncertainty.

Mode A uses independent workers with one coordinator handling shared edits and feedback. Mode B follows the same records and guards but talks directly to the human. If delegation is unavailable, process tasks serially using the same contracts. For a family of unvalidated jobs, use an interactive canary before fan-out unless the user explicitly chooses otherwise.

Record job receipts before replacing job=pending with a real ID. Each state change gets its own ledger row with evidence. On return, leave each submitted job either verifiably terminal or explicitly handed off with last observed state, monitoring instructions, and next owner/resumer. Do not label a live reservation terminal merely because a round ended.

## Publication guard and completion

Apply this guard to every marker write, including job updates, blockers, and final replacement:

1. Rescan the exact ID and reread its task record. Require exactly one marker, the expected owner and latest Attempt number, and matching dispatched task text and canonical context. The Attempt must not have been superseded/cancelled. Pending fill-from-data work follows the same claim/Attempt discipline.
2. If any check fails, do not change the marker or promote the obsolete result as the current conclusion. Save late evidence in Working notes under its originating Attempt. Do not touch a newer owner's active Attempt or final Outcome.
3. Read a narrow window and replace the full exact current marker. After a failed edit, reread and repeat all guards once before retrying. Report failure after that; never replace by ID alone or rewrite the whole worknote.

On success, first persist job evidence, reusable learnings, and task results. Recheck the guard before promotion. If a worknote-level conclusion warrants promotion, call promote-conclusion and read back its bullet; retry once on failure. Then fill Outcome once with conclusion and verified promoted value (or explicit failure). Recheck the guard immediately before final replacement. Record publication outcome in Working notes and return computation success separately from publication failure.

An already completed Outcome may be republished for the same task after the guard succeeds; do not rerun computation or refill Outcome. If task/context changes after Outcome was filled, preserve that completed task, allocate a fresh ID for the revised request, and reserve a new record. This avoids reopening immutable completion history.

These checks are optimistic, not an atomic compare-and-swap across files. If a concurrent edit is detected after promotion/publication, retain evidence, report the conflict, and reconcile the index with the current writer before continuing. Do not erase another session's edits to simulate rollback.

## Human edits, supersession, and blockers

Deleting a marker cancels that dispatch's permission to publish. Changing task text or inherited context supersedes its intent. A status scan only reports this. An authorized execution/reconciliation pass closes the old active Attempt with the cancellation/supersession reason (or records the reason in Working notes for an already closed Attempt); a revised unfinished task gets a new Attempt and claim after the old worker is stopped or handed off. Underlying jobs remain at their actual observed states. Cancel them only with authorization, and append cancelled only after confirmation. If an old worker returns later, retain its evidence without publishing it over the new intent.

For a blocker, save partial results and append a blocker entry with evidence, then guardedly mark BLOCKED and close the Attempt. Return to the coordinator; do not wait inside a worker. Batch actionable questions once per collection round, respecting the host's question limits rather than inventing an unlimited question tool.

On answer, use answer-blocker only if the latest entry is unanswered. If it already contains the same answer, reuse it; if inline and stored answers conflict, ask which applies. A BLOCKED task with no answer is awaiting input, not runnable. Resume with a fresh Attempt carrying the existing evidence, question, answer, and scoped context; avoid repeating failed approaches. Explicit Mode B takeover can instead continue interactively.

Refresh Current focus after dispatch and collection to include open work and immediate next steps only; clear it when none remain. Summarize unresolved live jobs and unpublished results. Do not start notifications, schedules, or additional jobs merely as cleanup.

## Status

Status is read-only: no stamping, claiming, repairs, execution workers, or job cancellations. Use the scanner plus bounded memory reads or a read-only query worker. Report IDs (use `—` for unstamped), state, owner, job ID, age, and the evidence/reason for reconciliation. Marker-only table output is insufficient for this command.

| State or finding | Evidence |
|---|---|
| pending | Unclaimed placeholder |
| running | Active owner/job; label ledger-only information as last recorded |
| blocked / blocked+answered | Latest blocker or inline answer, with conflicts surfaced |
| stale-claim | Owner confirmed inactive and job terminal, or abandoned pending claim confirmed by owner/runtime evidence |
| orphaned-job | Active/last-recorded-running job without its task marker; cancellation is not inferred |
| done-but-unwritten | Task Outcome exists but publication failed or marker remains |
| task-drift / context-drift | Current intent differs from the latest Attempt snapshot |
| promotion-drift | Outcome claims an index promotion but no matching task pointer exists; also report explicit promotion failure |
| liveness-unknown | Job/owner cannot be resolved; do not equate with termination |

Multiple findings can apply to one task. A missing legacy snapshot is uncertainty to reconcile, not a match. Lookup scheduler state read-only when available and authorized; status never appends the observation. Acting on findings happens in an execution invocation.
