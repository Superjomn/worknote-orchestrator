#!/usr/bin/env bash
# The deterministic "human edit" performed BETWEEN phase 1 and phase 2.
#
# Simulates the human treating the worknote as a live control surface. Three edits to
# HumanEdit.md (each also documented so it can be done by hand instead):
#   1. CANCEL     — delete the entire `<<RUNNING#1 ...>>` bullet line (marker vanishes).
#   2. SUPERSEDE  — rewrite marker #2's `task:` from `sweep dp=4` to `sweep dp=4 with bs=128`.
#   3. LOST-RESULT — delete the entire `<<RUNNING#3 ...>>` bullet line (job mock-0003 already
#                    finished, so its result must be recovered from memory, not the worknote).
set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WN="$SCENARIO_DIR/HumanEdit.md"

python3 - "$WN" <<'PY'
import re, sys
p = sys.argv[1]
lines = open(p).read().splitlines(keepends=True)
out = []
cancel = supersede = lost = False
for ln in lines:
    if "RUNNING#1" in ln:          # cancel: drop the whole bullet
        cancel = True
        continue
    if "RUNNING#3" in ln:          # lost-result: drop the whole bullet
        lost = True
        continue
    if "RUNNING#2" in ln and "with bs=128" not in ln:   # supersede: re-scope task text
        ln = ln.replace("task: sweep dp=4", "task: sweep dp=4 with bs=128")
        supersede = True
    out.append(ln)
open(p, "w").write("".join(out))
print(f"cancel(#1)={cancel}  supersede(#2)={supersede}  lost-result(#3)={lost}")
PY

echo "mutate.sh applied to $WN"
echo "  #1 marker deleted (cancel), #2 task re-scoped to 'sweep dp=4 with bs=128' (supersede),"
echo "  #3 marker deleted (lost-result, job already finished)."
