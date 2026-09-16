#!/usr/bin/env bash
# assert.sh <case-id> <scratch-dir>
#
# Grep-based post-conditions for each mock-memory case. Run AFTER the agent has
# executed the case's action (see CASES.md). Exits non-zero on the first failed
# assertion. Refusal cases (P3/P4/P5) and no-mirror cases (C3) assert the store
# is byte-identical to the setup.sh snapshot.
set -uo pipefail

CASE="${1:?usage: assert.sh <case-id> <scratch-dir>}"
SCRATCH="${2:?usage: assert.sh <case-id> <scratch-dir>}"

case "$CASE" in
  R[1-6]) exec python3 "$(dirname "${BASH_SOURCE[0]}")/reliability.py" assert "$CASE" "$SCRATCH" ;;
esac

STORE="$SCRATCH/research-memory"
ORIG="$SCRATCH/research-memory.orig"
MEM="$STORE/MEMORY.md"
CFG="$STORE/configs.md"

fails=0
ok()   { printf '  ok   — %s\n' "$1"; }
bad()  { printf '  FAIL — %s\n' "$1"; fails=$((fails + 1)); }

# check <description> <test-cmd...> — passes if the command succeeds.
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
# checkn <description> <test-cmd...> — passes if the command FAILS (negated).
checkn() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then bad "$d"; else ok "$d"; fi; }

count() { grep -cF -- "$2" "$1" 2>/dev/null || true; }
# eq <description> <expected> <actual>
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected $2, got $3)"; fi; }
# le <description> <limit> <actual>
le() { if [ "$3" -le "$2" ]; then ok "$1 (got $3)"; else bad "$1 (got $3 > $2)"; fi; }

echo "=== assert $CASE ==="
case "$CASE" in

  P1) # promote happy path: exactly one task-1 bullet, no template example, dated pointer.
    n=$(count "$MEM" '→ tasks/task-1.md')
    eq "exactly one → tasks/task-1.md bullet" 1 "$n"
    checkn "template example bullet removed from Validated conclusions" \
      grep -q 'baseline config X reaches 1200' "$MEM"
    check "bullet carries a date + → tasks/task-1.md pointer" \
      grep -Eq '— .*[0-9]{4}-[0-9]{2}-[0-9]{2}.*→ tasks/task-1\.md$' "$MEM"
    ;;

  P2) # duplicate promotion updates in place: still one bullet, now the NEW text.
    n=$(count "$MEM" '→ tasks/task-1.md')
    eq "still exactly one → tasks/task-1.md bullet (no duplicate)" 1 "$n"
    check "bullet carries the NEW text token (UPDATED-1500tok)" \
      grep -q 'UPDATED-1500tok' "$MEM"
    checkn "old text (1000 tok/s) replaced" grep -q '1000 tok/s' "$MEM"
    ;;

  P3|P4|P5|C5|J1|S2) # refusals: store byte-identical to the snapshot (no mutation) + right reason.
    if diff -r "$ORIG" "$STORE" >/dev/null 2>&1; then
      ok "store byte-identical to snapshot (action refused, no mutation)"
    else
      bad "store changed — refusal case must not mutate any file"
      diff -r "$ORIG" "$STORE" || true
    fi
    REF="$SCRATCH/refusal.txt"
    if [ -f "$REF" ]; then
      ok "refusal.txt captured"
      # Per-case keyword: the refusal message must name the violated rule, not just any refusal.
      case "$CASE" in
        P3) check "refusal names the missing evidence pointer" grep -qi 'evidence' "$REF" ;;
        P4) check "refusal names the missing task file (task-2)" grep -q 'task-2' "$REF" ;;
        P5) check "refusal names the empty focus text" grep -qi 'empty' "$REF" ;;
        J1) check "refusal names the invented status (released)" grep -q 'released' "$REF" ;;
        C5) check "refusal names the evidence job state (failed)" grep -qi 'failed' "$REF" ;;
        S2) check "refusal names the DONE/changelog/forward-looking rule" \
              grep -qiE 'changelog|forward-looking|completion log|DONE' "$REF" ;;
      esac
    else
      bad "refusal.txt not found — refusal case must write its verbatim message to \$S/refusal.txt"
    fi
    ;;

  C1) # untested->working: row flipped, mirror added, template examples deleted.
    check "configs.md baseline-v2 row is now working" \
      grep -Eq '^\| baseline-v2 .*\| working \|' "$CFG"
    check "MEMORY.md Reference configs mirrors baseline-v2 @ working" \
      grep -q 'baseline-v2 → configs.md#baseline-v2 (status: working)' "$MEM"
    checkn "configs.md template example row deleted (first real row hygiene)" \
      grep -q 'e.g. baseline-v2 / configs/baseline.yaml' "$CFG"
    checkn "MEMORY.md Reference-configs template example deleted" \
      grep -q 'working baseline → configs.md#baseline-v2' "$MEM"
    ;;

  C2) # working->superseded: mirror REPLACED in place, exactly one baseline-v2 line.
    n=$(count "$MEM" 'baseline-v2 → configs.md')
    eq "exactly one baseline-v2 Reference-configs line (replaced, not duplicated)" 1 "$n"
    check "MEMORY.md mirror now (status: superseded)" \
      grep -q 'baseline-v2 → configs.md#baseline-v2 (status: superseded)' "$MEM"
    check "configs.md baseline-v2 row is now superseded" \
      grep -Eq '^\| baseline-v2 .*\| superseded \|' "$CFG"
    ;;

  C3) # untested->failed: no mirror -> MEMORY.md byte-identical; configs row failed.
    if diff "$ORIG/MEMORY.md" "$MEM" >/dev/null 2>&1; then
      ok "MEMORY.md byte-identical (no mirror on → failed)"
    else
      bad "MEMORY.md changed — → failed must not touch MEMORY.md"
      diff "$ORIG/MEMORY.md" "$MEM" || true
    fi
    check "configs.md baseline-v2 row is now failed" \
      grep -Eq '^\| baseline-v2 .*\| failed \|' "$CFG"
    ;;

  C4) # working->failed regression: mirror UPDATED to failed, no stale working line.
    n=$(count "$MEM" 'baseline-v2 → configs.md')
    eq "exactly one baseline-v2 Reference-configs line (updated, not duplicated)" 1 "$n"
    check "MEMORY.md mirror now (status: failed)" \
      grep -q 'baseline-v2 → configs.md#baseline-v2 (status: failed)' "$MEM"
    checkn "no stale (status: working) baseline-v2 line survives" \
      grep -q 'baseline-v2 → configs.md#baseline-v2 (status: working)' "$MEM"
    check "configs.md baseline-v2 row is now failed" \
      grep -Eq '^\| baseline-v2 .*\| failed \|' "$CFG"
    ;;

  J2) # add-job unregistered config ref: jobs row appended + untested configs row auto-added.
    JOB="$STORE/jobs.md"
    check "jobs.md has the srun-800 row" grep -q 'srun-800' "$JOB"
    check "jobs.md row uses the resolvable ref configs.md#pmt32" \
      grep -q 'configs.md#pmt32' "$JOB"
    n=$(grep -cE '^\| pmt32 ' "$CFG")
    eq "exactly one pmt32 configs row (ref normalized to its anchor)" 1 "$n"
    check "the pmt32 configs row is untested with evidence citing srun-800" \
      grep -Eq '^\| pmt32 .*\| untested \|.*srun-800' "$CFG"
    ;;

  S1) # set-focus prune: Current focus rewritten to ≤5 forward-looking bullets, no DONE changelog.
    # Extract the "## Current focus" section (lines up to the next "## " heading).
    focus=$(awk '/^## Current focus/{f=1;next} /^## /{f=0} f' "$MEM")
    nb=$(printf '%s\n' "$focus" | grep -cE '^- ' || true)
    le "Current focus has ≤5 bullets" 5 "$nb"
    if [ "$nb" -ge 1 ]; then ok "Current focus is non-empty (not a vacuous wipe)"; else bad "Current focus is empty — expected the forward-looking bullets"; fi
    check "the new forward-looking bullet (tp=16 variant) landed" \
      grep -qF 'tp=16 variant' "$MEM"
    if printf '%s\n' "$focus" | grep -qE 'DONE #?[0-9]'; then
      bad "Current focus still carries DONE #N changelog bullets"
    else
      ok "no DONE #N changelog bullets in Current focus"
    fi
    check "other sections intact (Validated conclusions heading present)" \
      grep -q '^## Validated conclusions' "$MEM"
    ;;

  C6) # non-best working transition: configs row working, but NO new Reference line (MEMORY untouched).
    if diff "$ORIG/MEMORY.md" "$MEM" >/dev/null 2>&1; then
      ok "MEMORY.md byte-identical (non-family-best working → no Reference line)"
    else
      bad "MEMORY.md changed — a non-best working transition must not add a Reference line"
      diff "$ORIG/MEMORY.md" "$MEM" || true
    fi
    check "configs.md family-a-alt row is now working" \
      grep -Eq '^\| family-a-alt .*\| working \|' "$CFG"
    checkn "no family-a-alt Reference-configs line added" \
      grep -q 'family-a-alt → configs.md' "$MEM"
    ;;

  J3) # pool release: appended a cancelled row for srun-900; never the invalid 'released' status.
    JOB="$STORE/jobs.md"
    check "jobs.md srun-900 has a cancelled row" \
      grep -Eq '^\| .*srun-900 .*\| cancelled \|' "$JOB"
    checkn "no 'released' status column anywhere in jobs.md" \
      grep -Eq '\| released \|' "$JOB"
    # The release reason must live in the result ptr (col 8), not be empty/dash.
    reason=$(awk -F'|' '/srun-900/ && $7 ~ /cancelled/ {gsub(/^[[:space:]]+|[[:space:]]+$/,"",$8); r=$8} END{print r}' "$JOB")
    if [ -n "$reason" ] && [ "$reason" != "—" ] && [ "$reason" != "-" ]; then
      ok "cancelled row records a release reason in the result ptr ($reason)"
    else
      bad "cancelled srun-900 row has no release reason in the result ptr"
    fi
    ;;

  K1) # add-script: helper relocated under scripts/, root copy gone, cited in runbook §Collect.
    RB="$STORE/runbook.md"
    check "scripts/collect_tps.py exists" test -f "$STORE/scripts/collect_tps.py"
    checkn "no stray collect_tps.py at the memory root" test -f "$STORE/collect_tps.py"
    # The Collect section (up to the next "## " heading) must cite the script.
    collect=$(awk '/^## Collect/{f=1;next} /^## /{f=0} f' "$RB")
    if printf '%s\n' "$collect" | grep -q 'collect_tps.py'; then
      ok "runbook §Collect cites collect_tps.py"
    else
      bad "runbook §Collect does not cite collect_tps.py"
    fi
    ;;

  L1) # near-cap promote: ≤150 lines, new bullet present, no pointer dropped.
    lines=$(wc -l < "$MEM")
    le "MEMORY.md ≤150 lines" 150 "$lines"
    check "new bullet → tasks/task-90.md present" grep -q '→ tasks/task-90\.md' "$MEM"
    if [ -f "$SCRATCH/pointers.orig" ]; then
      missing=0
      while IFS= read -r ptr; do
        [ -z "$ptr" ] && continue
        grep -qF -- "$ptr" "$MEM" || { bad "pre-existing pointer dropped: $ptr"; missing=$((missing + 1)); }
      done < "$SCRATCH/pointers.orig"
      [ "$missing" = 0 ] && ok "all pre-existing → tasks/task-*.md pointers preserved"
    else
      bad "pointers.orig snapshot missing (setup.sh L1 not run?)"
    fi
    ;;

  D1) # drift detection: status output has a promotion-drift row for id 2.
    OUT="$SCRATCH/status-output.txt"
    if [ -f "$OUT" ]; then
      if grep -E 'promotion-drift' "$OUT" | grep -q '2'; then
        ok "status output reports promotion-drift for id 2"
      else
        bad "status output has no promotion-drift row for id 2"
      fi
    else
      bad "status-output.txt not found — run the /worknote-orchestrate status step and save its table there"
    fi
    ;;

  W1) # read-back failure: Outcome written once with promoted: FAILED.
    T="$STORE/tasks/task-1.md"
    no=$(count "$T" '## Outcome')
    eq "Outcome section present exactly once" 1 "$no"
    np=$(grep -c 'promoted:' "$T" 2>/dev/null || true)
    eq "exactly one promoted: line (Outcome write-once)" 1 "$np"
    check "promoted: FAILED recorded (drift stays visible)" grep -q 'promoted: FAILED' "$T"
    ;;

  X1) # context hiding: the #2 dispatch prompt carries the global + S2 chain, never S1's.
    WN="$SCRATCH/Scratch.md"
    D="$SCRATCH/dispatch-2.txt"
    if [ -f "$D" ]; then
      ok "dispatch-2.txt captured"
      check "dispatch carries the global context block"   grep -q 'GLOBAL-CTX-AAA' "$D"
      check "dispatch carries its own section's context"  grep -q 'SEC2-CTX-CCC' "$D"
      checkn "dispatch HIDES the sibling section's context" grep -q 'SEC1-CTX-BBB' "$D"
    else
      bad "dispatch-2.txt not found — build the #2 dispatch prompt and save it to \$S/dispatch-2.txt"
    fi
    if diff -q "$SCRATCH/Scratch.md.orig" "$WN" >/dev/null 2>&1; then
      ok "worknote byte-identical (prompt-building performs no writes)"
    else
      bad "worknote changed — building a dispatch prompt must not write"
    fi
    ;;

  X2) # id-stamping skips context blocks: only the two real placeholders get ids.
    WN="$SCRATCH/Scratch.md"
    checkn "no context block was stamped (no <<!# anywhere)" grep -q '<<!#' "$WN"
    check "global context block intact and un-stamped" grep -q '<<! GLOBAL-CTX-AAA' "$WN"
    check "section context block intact and un-stamped" grep -q '<<! SEC1-CTX-BBB' "$WN"
    check "first real placeholder stamped #1" grep -q '<<#1 measure baseline throughput>>' "$WN"
    check "second real placeholder stamped #2" grep -q '<<#2 profile the decode phase>>' "$WN"
    nb=$(grep -c '<<!' "$WN" 2>/dev/null || true)
    eq "still exactly 2 context blocks" 2 "$nb"
    ;;

  X3) # context-drift detection: status output has a context-drift row for id 1.
    OUT="$SCRATCH/status-output.txt"
    if [ -f "$OUT" ]; then
      if grep -E 'context-drift' "$OUT" | grep -q '1'; then
        ok "status output reports context-drift for id 1"
      else
        bad "status output has no context-drift row for id 1"
      fi
    else
      bad "status-output.txt not found — run the /worknote-orchestrate status step and save its table there"
    fi
    if diff -r "$ORIG" "$STORE" >/dev/null 2>&1; then
      ok "store byte-identical to snapshot (status is read-only)"
    else
      bad "store changed — a status scan must not mutate any file"
      diff -r "$ORIG" "$STORE" || true
    fi
    ;;

  Q1|Q2|Q3|Q4|Q5) # query cases: READ-ONLY — store byte-identical + answer.txt written + right answer.
    ANS="$SCRATCH/answer.txt"
    if diff -r "$ORIG" "$STORE" >/dev/null 2>&1; then
      ok "store byte-identical to snapshot (query is read-only)"
    else
      bad "store changed — a query must not mutate any file"
      diff -r "$ORIG" "$STORE" || true
    fi
    if [ -f "$ANS" ]; then
      ok "answer.txt captured"
    else
      bad "answer.txt not found — query case must write the returned answer to \$S/answer.txt"
    fi
    case "$CASE" in
      Q1) # reproduce the last job: names srun-950 + the submit command, NOT the older srun-900.
        check "answer names the last job id (srun-950)" grep -qF 'srun-950' "$ANS"
        check "answer carries the submit command fragment" \
          grep -qF 'sbatch --nodes=2 run.sh' "$ANS"
        checkn "answer does NOT cite the earlier job (srun-900) as the reproduction target" \
          grep -qF 'srun-900' "$ANS"
        ;;
      Q2) # list all nsys reports: all three .nsys-rep paths, never the non-nsys ptr.
        check "answer lists /logs/prof-a.nsys-rep (jobs.md)" grep -qF '/logs/prof-a.nsys-rep' "$ANS"
        check "answer lists /logs/prof-b.nsys-rep (jobs.md)" grep -qF '/logs/prof-b.nsys-rep' "$ANS"
        check "answer lists /logs/prof-c.nsys-rep (task file)" grep -qF '/logs/prof-c.nsys-rep' "$ANS"
        checkn "answer does NOT list the non-nsys ptr (/logs/plain.txt)" \
          grep -qF '/logs/plain.txt' "$ANS"
        ;;
      Q3) # foreign reference: fact from Prod.memory + a pointer into it; foreign store untouched.
        check "answer carries the foreign fact (PROD-BATCH-512)" grep -qF 'PROD-BATCH-512' "$ANS"
        check "answer cites an evidence pointer into Prod.memory/" grep -qF 'Prod.memory' "$ANS"
        if diff -r "$SCRATCH/Prod.memory.orig" "$SCRATCH/Prod.memory" >/dev/null 2>&1; then
          ok "foreign store (Prod.memory) byte-identical (query is read-only)"
        else
          bad "foreign store changed — a query must not mutate a foreign store"
          diff -r "$SCRATCH/Prod.memory.orig" "$SCRATCH/Prod.memory" || true
        fi
        ;;
      Q4) # worknote-markdown fallback: fact + a pointer to Notes.md (no Notes.memory/ existed).
        check "answer carries the markdown-only fact (NOTES-ONLY-XYZ)" grep -qF 'NOTES-ONLY-XYZ' "$ANS"
        check "answer cites a pointer to Notes.md (worknote-markdown fallback)" \
          grep -qF 'Notes.md' "$ANS"
        ;;
      Q5) # miss: explicit NOT FOUND, no invented specifics.
        check "answer is an explicit NOT FOUND / no-record miss" \
          grep -qiE 'not found|no (evidence|record|entry)' "$ANS"
        checkn "answer invents no throughput number (no fabricated tok/s value)" \
          grep -Eq '[0-9]+ tok/s' "$ANS"
        ;;
    esac
    ;;

  *) echo "FATAL: unknown case-id '$CASE'" >&2; exit 2 ;;
esac

echo
if [ "$fails" = 0 ]; then
  echo "PASS $CASE"
  exit 0
else
  echo "FAIL $CASE ($fails failed assertion(s))"
  exit 1
fi
