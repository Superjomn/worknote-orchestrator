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

  P3|P4|P5|C5|J1) # refusals: store byte-identical to the snapshot (no mutation) + right reason.
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
