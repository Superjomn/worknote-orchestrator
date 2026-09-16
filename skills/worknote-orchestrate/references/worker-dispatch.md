# Worker dispatch

Resolve the selected placeholder with scanner `--id N --memory <store>`. Its context_chain is the complete applicable context; do not attach the whole scan or unrelated worknote sections. Independent tasks may execute concurrently, but their shared-file writes go through the coordinator's serialized writer queue. A worker sends an edit request and waits for confirmation before relying on the changed claim or memory. If the host lacks this coordination capability, run those tasks serially.

Use a bounded prompt such as:

```text
Complete one approved worknote task. Record blockers and return; the coordinator handles human input.
Workdir: <absolute directory>
Worknote: <absolute file>
Memory store: <absolute directory>
Task ID / owner / expected Attempt / token / fingerprint: <original dispatch values>
Guard command: <absolute scanner path, worknote/store paths, --id and all three --expect-* values>
Approved task and scope: <task text, strategy, resource limits>
Canonical context: <whitespace-collapsed chain joined by |, or none>
Context sources: <only this task's ordered blocks and headings>
Prior blocker answer: <answer or none>
Read: <absolute lifecycle reference>, <absolute memory SKILL.md>
Shared writer: <coordinator/channel; request and confirm each shared edit>
Return: task status, evidence pointers, pending jobs, and any publication failure.
```

The worker reads its own Brief, Attempts, and Working notes and the bounded memory index, then retrieves only needed details through memory query. Read the selected action reference when a memory operation is needed. Use available host tools, not assumed Claude-specific names or inherited environment variables.

Before submitting new work, check existing jobs and prior failed approaches. Record submission intent with a runner correlation token; recover uncertain submissions by that token before retrying. Follow the lifecycle's publication guard for every requested marker update. An obsolete worker may record observed job states and late evidence but cannot update the new claim, promote obsolete conclusions, or fill the newer task's Outcome.

Return one of `#N done`, `#N done (worknote not updated: reason)`, `#N BLOCKED: question`, or `#N RUNNING: job ID`, adding evidence/handoff detail as needed. Do not return full memory bodies. The coordinator verifies persisted changes, refreshes focus, and handles unanswered questions in a batch.
