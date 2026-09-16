# Memory action contracts

Use this reference for the selected write action only. File shapes are in [templates](../templates/); shared concurrency and evidence rules are in [SKILL.md](../SKILL.md). Do not perform an unrelated cleanup while executing an action.

Before writing, validate required arguments and evidence, resolve the actual target, and read the affected section. Missing stores are errors except for init. Remove italic template examples when adding the first real entry; this is the sole initialization exception to append-only history. Keep other records unchanged. Timestamps use local `YYYY-MM-DD HH:MM` with the project's timezone understood by participating sessions.

## Setup

### init <worknote-path>

Require an existing worknote and a nonexistent sibling `<Base>.memory/`. Copy MEMORY.md, configs.md, runbook.md, jobs.md, and blockers.md from this skill's templates, substituting the project name in the index heading. Do not overwrite an existing store; suggest joining it with link. Do not create task.md as a root file. Verify all five files and the heading; report any partial creation rather than retrying over it.

### link

Require an identified store and a git worktree. Create `./research-memory` pointing to the absolute store, then add `/research-memory` to the exclude file resolved by `git rev-parse --git-path info/exclude`, creating its parent if needed and avoiding duplicate entries. Never edit .gitignore. Refuse an existing file or symlink at the destination, including a broken symlink; report its target when available. Verify the resolved link and exclusion, including in linked worktrees. If exclusion fails after link creation, report the partial result.

## Task and job records

### task-note <id> <text>

Require a positive ID and a specified update. Initialize `tasks/task-<id>.md` reserved by `wn_allocate.py`, or create it from [task.md](../templates/task.md) for a pre-existing human-stamped ID, filling the Brief with task, workdir, worknote, canonical context, and blocker references. An ID-only reservation may leave Attempts and Outcome empty; do not fabricate an executed Attempt from the template example.

On dispatch, append Attempt N+1 with the exact approved task text, owner, unique token, scanner fingerprint, timestamp, and canonical context. Context is whitespace-collapsed block texts joined with ` | `, outermost to innermost, or `none`. The owner may update its active Attempt's tried/jobs/outcome/next-step fields until it closes; its task and context snapshot remain fixed. Closed Attempts are immutable. A restart appends a new Attempt; it never replaces prior history. Legacy Attempts without owner/task snapshots are not proof that an old worker still owns the task: reconcile before publishing.

For an orchestrated verdict, promotion, blocker, or Outcome, the shared writer must run the original owner/token/fingerprint guard immediately before the edit. A failed guard permits only truthful job observations and old-attempt evidence.

Working notes are mutable scratch. Late results from an obsolete dispatch go there with the old Attempt number and evidence; never rewrite a closed Attempt or newer owner's state. Record its originating token and input fingerprint. Fill the final Outcome once, only for the current task's verified completion, after promotion read-back when applicable. Use `promoted: none` when no promotion is needed, or `FAILED (<reason>)` on failed verification. Record subsequent publication success/failure in Working notes so a failed worknote edit does not require rewriting Outcome. Completed Outcomes are not reopened: changed intent after completion gets a fresh ID.

Verify the intended Brief/Attempt/notes/Outcome change and that closed Attempts and prior final Outcome remain unchanged.

### add-job <fields>

Require all columns: timestamp, job id, purpose, config ref, owner, status, result pointer. Cite submission receipts, scheduler observations, logs, or equivalent evidence; a terminal claim needs evidence for that state. Status is one of `submitted`, `running`, `finished`, `failed`, `cancelled`. `unknown` is a query result, not a stored status; a confirmed released/scancelled reservation is `cancelled`, with the release reason in the result pointer.

For orchestrated jobs include task ID and attempt token in the purpose field on every row. Append one row per observed state change for that job ID. Never fold one job's terminal state into another job's row. Deleting a worknote marker or superseding an Attempt is not evidence of cancellation. For an unregistered config reference, first add an `untested` configs row using the reference anchor as ID, supplied workdir/knobs, and the job receipt as evidence. Refuse if required config fields cannot be established. Then append the job row; report a partial config-only write if the second edit fails.

Verify one new row, unchanged prior real rows, valid status, and a resolvable config reference. The latest row per job is its last recorded observation, not a guarantee that the scheduler still agrees.

### update-config-status <id> <status>

Require a registered config and evidence. Allowed transitions: untested → working or failed; failed → untested after editing; working → failed or superseded. Repeating an already established status is a no-op unless the user asks to refresh its evidence. Refuse other transitions.

A working verdict requires the cited job's latest ledger row to be `finished` and evidence of success for the config's actual purpose. A failed run's useful sub-effect belongs in knobs/evidence, not a working verdict. Name the observed state when refusing.

Update the target configs row. Reference configs in MEMORY.md is a curated shortlist: add a newly working config only when evidence or explicit user selection establishes it as the family-best/representative. Replace its predecessor's pointer when appropriate; do not mirror every working row or infer superiority without evidence. If the target already has a reference, update its status in place, including working → failed/superseded. Remove its pointer only for a successor replacement or explicit removal request. Verify the target row, evidence, and matching reference if affected; other rows remain unchanged.

## Learnings and blockers

### add-learning <text>

Require a supported learning with its evidence. Place it in runbook Environment (setup), Submit (launch), Monitor (status resolution), Collect (extraction/helpers), or Pitfalls (gotcha and fix). Split genuinely different topics across their matching sections. Verify the fact is discoverable in the correct section and unrelated content is unchanged.

### add-script <name> <description>

Require a supplied or authorized helper and description. Resolve the destination under the store's scripts directory; reject path traversal or symlink escape, and do not overwrite an unrelated helper. Place or move it there and cite its path, purpose, and usage in runbook Collect. Verify both placement and citation. These are two edits, not an atomic transaction: report and repair a partial result within authorization. Do not execute a helper solely to register it.

### add-blocker <fields>

Require ID/title, timestamp, workdir, placeholder ref, task-file pointer, Question, and Evidence. Append a new entry at EOF using [blockers.md](../templates/blockers.md), with an empty Answer. Re-blocking appends another entry with the same ID. Verify the fields, empty Answer, and unchanged historical entries.

### answer-blocker <id> <text>

Require a nonempty answer and a matching entry. Target only the latest matching entry. If its Answer is already nonempty, refuse even when an older entry remains unanswered. Never overwrite or backfill an older question as a side effect. Fill only the latest entry's empty Answer and verify every other byte is unchanged. Reusing an existing answer during resumption does not call this action again.

## Curated index

### promote-conclusion <id> <text>

Require an existing task file and evidence-backed conclusion. Add one Validated conclusions bullet ending with an evidence pointer, timestamp, and `→ tasks/task-<id>.md`; update an existing bullet for that task instead of duplicating it. Remove example bullets on first use. If needed, compress older text while retaining evidence and task pointers to stay within 150 lines; report a capacity blocker if that cannot be done without losing meaning.

For orchestrated promotion include the original attempt token and fingerprint in the bullet. Read back the bullet under Validated conclusions and verify its content, pointer, and those values. The caller may retry an unsuccessful promotion/read-back once, then records failure explicitly. Do not claim promotion merely because an edit was attempted.

### set-focus <text>

Rewrite only Current focus with at most five forward-looking bullets. Drop completed/superseded items; do not add DONE changelog entries. Empty text is valid when the caller explicitly clears focus or the round has no remaining work: leave the section empty. Missing input with no clearing intent is a clarification need, not permission to erase active work. Verify the section, bullet limit, and byte-identical remainder of MEMORY.md.
