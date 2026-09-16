# Read-only memory queries

## show-summary

Read MEMORY.md directly (at most 150 lines) and summarize current focus, validated conclusions, and reference pointers. A missing local store is an error; suggest init. Do not repair or curate while summarizing.

## query [<worknote>] <question>

Require a nonempty question. Without a worknote, use the identified local store. With a worknote, require that file to exist, resolve its sibling `<Base>.memory/`, and search there first. If that foreign store is missing or lacks an answer, search the specified worknote with bounded windows; never write to the foreign store or worknote.

Read MEMORY.md first, then the relevant topic ledger (jobs/configs/runbook/blockers), then pointed-to task files and helpers. Stop only when the whole question is answered. For exhaustive requests, search every relevant source, not just the first matching pointer. Template examples are not evidence. Report conflicts or stale observations rather than choosing a convenient answer.

For job status use the latest row for that job, distinguishing last recorded state from current verified liveness. For “last job” reproduction, select the most recently submitted job (submission timestamp, ledger order as a tie-breaker), not an older job whose status was updated last; when submission data is absent, label the selection as the last recorded job. Follow that job's config reference and applicable runbook Submit recipe, citing each part. Listing reports may require jobs result pointers, task notes, and runbook Collect; deduplicate paths without dropping evidence.

Every factual claim needs a file plus row, heading, anchor, or line pointer. Aim for ten lines, but expand for requested completeness. If only part is supported, return that part and identify the missing facts and sources searched. If nothing answers the question, return `NOT FOUND in <what was searched>`. Never invent a value or silently omit part of a multipart question.

Use a permitted read-only worker for broad retrieval, or bounded direct searches when delegation is unavailable or disproportionate. Pass absolute paths, the question, and this reference; return the answer itself, not raw file bodies. Do not write, initialize, normalize, or repair anything during query/status. Test captures belong outside the queried store.
