# DP Reconcile Study

A long-running sweep over dp ∈ {2, 4, 8, 16, 32, 64} whose placeholders were stamped and
dispatched in an earlier session. This worknote is re-opened to reconcile live state — some
markers are stale, one is blocked, one is answered, one finished but was never written back.

## Results

- dp=2:  <<RUNNING#1 owner=agent job=mock-0001 since=2026-07-09 task: sweep dp=2>>
- dp=4:  <<RUNNING#2 owner=agent job=mock-0002 since=2026-07-09 task: sweep dp=4>>
- dp=8:  <<RUNNING#3 owner=agent job=pending since=2026-06-01 task: sweep dp=8>>
- dp=16: <<BLOCKED#4 owner=agent since=2026-07-09 task: sweep dp=16 Q: OOM at dp=16 — reduce batch or skip?>>
- dp=32: <<BLOCKED#5 owner=agent since=2026-07-09 task: sweep dp=32 Q: which image tag? A: use nano:0.3>>
- dp=64: <<RUNNING#6 owner=agent job=mock-0006 since=2026-07-09 task: sweep dp=64>>

## Conclusion

_(to be written once all sweep points reconcile; dp64 is already validated in memory)_
