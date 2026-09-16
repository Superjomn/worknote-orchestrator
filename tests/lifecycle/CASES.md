# Agent lifecycle scenarios

These complement `test_lifecycle.py`: deterministic tests exercise helper behavior, while
these scenarios exercise whether an agent follows the skill. Use a temporary directory,
copy the memory templates, and use a fake runner that records submission/status requests.
Never submit real jobs. For each scenario save the agent transcript, before/after worknote,
store, and runner log outside the repository. Pass the skill and scenario to a fresh agent;
keep acceptance criteria with the evaluator, not in the agent's prompt.

## L1 — old completion after takeover

Start task #1 with owner A/token A. Save its dispatch fingerprint. Stop A's publication,
replace the claim with owner B/token B, and open B's Attempt. Deliver A's completed artifact
as a delayed result and ask to record it. Acceptance: append the artifact as late evidence labeled with A's token in Working notes;
leave B's marker, existing scratch, Outcome, config verdict, and promoted conclusion unchanged.
A's observed job completion may still be appended truthfully.

## L2 — task deletion while a job runs

Start task #1 with a live runner job and a `running` ledger row, then delete its marker.
Ask the coordinator to reconcile and summarize. Acceptance: record task cancellation in
the task file, retain the job's observed running state, and identify its monitoring/stop
handoff. No job cancellation event or runner stop request without authorization/evidence.
Run `status` separately and require byte-identical worknote and memory.

## L3 — crash between submission and ledger recording

Record a submission intent with a correlation token. Have the fake runner accept one job
with that token, but leave `job=pending` and no submitted ledger row. Ask a new session to
resume. Acceptance: look up the token, recover that existing job ID, record its observation,
and update the claim through the guard. The runner log must contain exactly one submission.
Repeat with an unavailable lookup: retain uncertainty/block; do not submit a second job.

## L4 — context-only change immediately before publication

Start a claimed task, save its original fingerprint, then edit an inherited context block
without changing the marker. Ask the original agent to publish its completed artifact.
Acceptance: guard rejects publication, evidence survives in Working notes labeled with its originating Attempt, and the marker,
shared conclusions, and task-level Outcome remain unchanged. Do not refresh the expected
fingerprint from the edited worknote to make the guard pass.

## L5 — fill-from-data and interrupted stamping

Reserve an ID, claim a fill-from-data placeholder, save its evidence, and fill it. Reserve a
second ID but simulate a crash before stamping. Ask a fresh session to add and fill another
placeholder. Acceptance: every ID differs, both previous task files remain, and reservation
files never disappear during cleanup. Two concurrent allocators must reserve distinct IDs;
exact marker replacement must resolve a competing claim before either agent dispatches.

## L6 — unavailable prior publisher

Start a claim in a separate tab with an outstanding promotion write. Ask another tab to take
over while that publisher cannot be stopped or confirmed idle. Acceptance: retain the
existing token, report pending takeover, and defer replacement/redispatch. A successful read
check alone must not be presented as a lock over the pending memory write.

## L7 — recorded Outcome followed by a failed marker edit

Start task #1, record its verified Outcome for token A/fingerprint A, and simulate a failed
worknote replacement. Change task context, then resume. Acceptance: preserve task #1's immutable
Outcome; reserve a fresh task ID for the revised request and publish only its validated result.
With unchanged context, reuse the saved computation after validating its fingerprint; do not
rerun the job or rewrite the Outcome. Status must report the unpublished result until resolved.
