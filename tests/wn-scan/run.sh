#!/usr/bin/env bash
# run.sh [scratch-dir]
#
# Deterministic, agent-free test suite for skills/worknote-orchestrate/scripts/wn_scan.py.
# Builds fixture worknotes in a scratch dir, runs the scanner, asserts on its JSON.
# Helper style mirrors tests/mock-memory/assert.sh so the output reads the same.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WN_SCAN="$SCRIPT_DIR/../../skills/worknote-orchestrate/scripts/wn_scan.py"
[ -f "$WN_SCAN" ] || { echo "FATAL: wn_scan.py not found: $WN_SCAN" >&2; exit 2; }

S="${1:-$(mktemp -d)}"
mkdir -p "$S"

fails=0
ok()   { printf '  ok   — %s\n' "$1"; }
bad()  { printf '  FAIL — %s\n' "$1"; fails=$((fails + 1)); }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
checkn() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then bad "$d"; else ok "$d"; fi; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected [$2], got [$3])"; fi; }

scan() { python3 "$WN_SCAN" "$@"; }
# jq-free JSON probing: a tiny python expression over the parsed document.
# jget <json-file> <python-expr over `d`>
jget() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2"; }

echo "=== wn-scan tests (scratch: $S) ==="

# The read-only proof (case 8) needs a baseline taken BEFORE the first invocation, so a
# first-run mutation cannot be captured as the baseline: `snap <path>` is called on each
# fixture the moment it is built, and case 8 diffs the whole snapshot tree at the end.
SNAP="$S/.snapshot"
rm -rf "$SNAP"; mkdir -p "$SNAP"
snap() { cp -r "$1" "$SNAP/$(basename "$1")"; }

# ---------------------------------------------------------------------------
# Fixture 1 — hiding + positional span + nesting + directives, all in one file.
# ---------------------------------------------------------------------------
WN1="$S/wn1.md"
cat > "$WN1" <<'EOF'
# Study

<<! GLOBAL-CTX-AAA @dir:/work/global >>

## Section 1

<<#1 measure baseline throughput>>

<<! SEC1-CTX-BBB @dir:/work/exp-a >>

<<#2 sweep tp=8>>

## Section 2

<<! SEC2-CTX-CCC >>

<<#3 @dir:/work/own collect nsys>>
EOF
snap "$WN1"

echo "--- 1: hiding (a chain carries only the enclosing sections)"
scan "$WN1" > "$S/out1.json" || bad "scan exited non-zero"
chain2=$(jget "$S/out1.json" '" | ".join(c["text"] for p in d["placeholders"] if p["id"]==2 for c in p["context_chain"])')
check "#2 chain has the global block"      grep -q 'GLOBAL-CTX-AAA' <<<"$chain2"
check "#2 chain has its own section block" grep -q 'SEC1-CTX-BBB'  <<<"$chain2"
checkn "#2 chain hides the sibling section" grep -q 'SEC2-CTX-CCC' <<<"$chain2"
chain3=$(jget "$S/out1.json" '" | ".join(c["text"] for p in d["placeholders"] if p["id"]==3 for c in p["context_chain"])')
check "#3 chain has the sibling-section block SEC2-CTX-CCC" grep -q 'SEC2-CTX-CCC' <<<"$chain3"
checkn "#3 chain hides SEC1-CTX-BBB"                        grep -q 'SEC1-CTX-BBB' <<<"$chain3"

echo "--- 2: positional span (a placeholder ABOVE the marker does not inherit it)"
n1=$(jget "$S/out1.json" '[len(p["context_chain"]) for p in d["placeholders"] if p["id"]==1][0]')
eq "#1 (above SEC1-CTX-BBB) inherits only the global block" 1 "$n1"
checkn "#1 does not inherit the later same-section block" \
  grep -q 'SEC1-CTX-BBB' <<<"$(jget "$S/out1.json" '" | ".join(c["text"] for p in d["placeholders"] if p["id"]==1 for c in p["context_chain"])')"

echo "--- 2b: a pending placeholder's task is its body (minus the stamped id)"
eq "#1 task extracted from the body" "measure baseline throughput" \
  "$(jget "$S/out1.json" '[p["task"] for p in d["placeholders"] if p["id"]==1][0]')"
eq "#3 task keeps its own directive text" "@dir:/work/own collect nsys" \
  "$(jget "$S/out1.json" '[p["task"] for p in d["placeholders"] if p["id"]==3][0]')"

echo "--- 4: @dir inheritance and per-placeholder override"
eq "#2 inherits the innermost @dir" "/work/exp-a" \
  "$(jget "$S/out1.json" '[p["effective_dir"] for p in d["placeholders"] if p["id"]==2][0]')"
eq "#1 inherits the global @dir" "/work/global" \
  "$(jget "$S/out1.json" '[p["effective_dir"] for p in d["placeholders"] if p["id"]==1][0]')"
eq "#3 own @dir overrides the chain" "/work/own" \
  "$(jget "$S/out1.json" '[p["effective_dir"] for p in d["placeholders"] if p["id"]==3][0]')"

echo "--- 5: context blocks are never placeholders"
eq "3 placeholders" 3 "$(jget "$S/out1.json" 'len(d["placeholders"])')"
eq "3 context blocks" 3 "$(jget "$S/out1.json" 'len(d["context_blocks"])')"
checkn "no context text leaked into placeholders" \
  grep -q 'CTX-' <<<"$(jget "$S/out1.json" '" ".join(p["body"] for p in d["placeholders"])')"
check "--id 2 emits just that placeholder object" \
  bash -c "python3 '$WN_SCAN' '$WN1' --id 2 | grep -q 'SEC1-CTX-BBB'"
checkn "--id 2 output hides the sibling section" \
  bash -c "python3 '$WN_SCAN' '$WN1' --id 2 | grep -q 'SEC2-CTX-CCC'"

# ---------------------------------------------------------------------------
# 3 — nesting order: preamble global, then # H1, then ## H2.
# ---------------------------------------------------------------------------
WN2="$S/wn2.md"
cat > "$WN2" <<'EOF'
<<! CTX-GLOBAL >>

# H1

<<! CTX-H1 >>

## H2

<<! CTX-H2 >>

<<#5 nested task>>

# H1b

<<#6 outside task>>
EOF
snap "$WN2"

echo "--- 3: nesting order is outermost -> innermost"
scan "$WN2" > "$S/out2.json" || bad "scan exited non-zero"
eq "#5 chain is [global, H1, H2] in order" "CTX-GLOBAL,CTX-H1,CTX-H2" \
  "$(jget "$S/out2.json" '",".join(c["text"] for p in d["placeholders"] if p["id"]==5 for c in p["context_chain"])')"
eq "#6 (next # H1b) keeps only the global block" "CTX-GLOBAL" \
  "$(jget "$S/out2.json" '",".join(c["text"] for p in d["placeholders"] if p["id"]==6 for c in p["context_chain"])')"
eq "#5 source headings recorded" "None,H1,H2" \
  "$(jget "$S/out2.json" '",".join(str(c["source_heading"]) for p in d["placeholders"] if p["id"]==5 for c in p["context_chain"])')"

# ---------------------------------------------------------------------------
# 6 — next_id: body refs do not inflate; max over three sources wins.
# ---------------------------------------------------------------------------
WN3="$S/wn3.md"
cat > "$WN3" <<'EOF'
# Ids

<<! CTX-NO-ID >>

<<#7 see issue #123 for background>>

<<RUNNING#8 owner=agent job=srun-1 since=2026-07-01 task: keep going>>
EOF
MEM3="$S/mem3"
mkdir -p "$MEM3/tasks"
: > "$MEM3/tasks/task-8.md"
: > "$MEM3/tasks/task-11.md"
cat > "$MEM3/blockers.md" <<'EOF'
# Blockers

## BLOCKED#9 — 2026-07-02
- Question: something
EOF
snap "$WN3"; snap "$MEM3"

echo "--- 6: next_id over all three sources"
scan "$WN3" --memory "$MEM3" > "$S/out3.json" || bad "scan exited non-zero"
eq "worknote marker max is 8 (body ref #123 ignored)" 8 \
  "$(jget "$S/out3.json" 'd["next_id_sources"]["worknote_markers"]')"
eq "task-file max is 11" 11 "$(jget "$S/out3.json" 'd["next_id_sources"]["task_files"]')"
eq "blocker max is 9"    9  "$(jget "$S/out3.json" 'd["next_id_sources"]["blockers"]')"
eq "next_id = max + 1"   12 "$(jget "$S/out3.json" 'd["next_id"]')"
eq "context block carries no id" 0 \
  "$(jget "$S/out3.json" 'len([b for b in d["context_blocks"] if "id" in b])')"
eq "without --memory, next_id falls back to the worknote alone" 9 \
  "$(scan "$WN3" > "$S/out3b.json"; jget "$S/out3b.json" 'd["next_id"]')"

# ---------------------------------------------------------------------------
# 7 — context-drift against the latest Attempt's `context:` line.
# ---------------------------------------------------------------------------
WN4="$S/wn4.md"
cat > "$WN4" <<'EOF'
# Drift

## S

<<! NEW-CTX-EEE >>

<<RUNNING#1 owner=agent job=srun-2 since=2026-07-02 task: drifted>>

<<RUNNING#2 owner=agent job=srun-3 since=2026-07-02 task: matched>>
EOF
MEM4="$S/mem4"
mkdir -p "$MEM4/tasks"
cat > "$MEM4/tasks/task-1.md" <<'EOF'
## Attempts
### Attempt 1 — 2026-07-02 10:00
- context: OLD-CTX-FFF
EOF
cat > "$MEM4/tasks/task-2.md" <<'EOF'
## Attempts
### Attempt 1 — 2026-07-02 10:00
- context: NEW-CTX-EEE
EOF
snap "$WN4"; snap "$MEM4"

echo "--- 7: context-drift"
scan "$WN4" --memory "$MEM4" > "$S/out4.json" || bad "scan exited non-zero"
eq "#1 drifts (Attempt records OLD-CTX-FFF)" "True" \
  "$(jget "$S/out4.json" '[p["context_drift"] for p in d["placeholders"] if p["id"]==1][0]')"
eq "#2 does not drift (Attempt matches)" "False" \
  "$(jget "$S/out4.json" '[p["context_drift"] for p in d["placeholders"] if p["id"]==2][0]')"

echo "--- 7b: an empty chain recorded as `none` does not drift"
WN5="$S/wn5.md"
printf '# NoCtx\n\n<<RUNNING#1 owner=agent job=srun-4 since=2026-07-02 task: no context here>>\n' > "$WN5"
MEM5="$S/mem5"; mkdir -p "$MEM5/tasks"
printf '## Attempts\n### Attempt 1 — 2026-07-02 10:00\n- context: none\n- tried: x\n\n## Outcome\n- context: LEAKED-FROM-OUTCOME\n' > "$MEM5/tasks/task-1.md"
snap "$WN5"; snap "$MEM5"
scan "$WN5" --memory "$MEM5" > "$S/out5.json" || bad "scan exited non-zero"
eq "empty chain vs recorded 'none' → no drift" "False" \
  "$(jget "$S/out5.json" '[p["context_drift"] for p in d["placeholders"] if p["id"]==1][0]')"
eq "chain resolution stops at the Attempt boundary (no Outcome leak)" 0 \
  "$(jget "$S/out5.json" '[len(p["context_chain"]) for p in d["placeholders"] if p["id"]==1][0]')"

echo "--- 7c: headings are ATX-only, and a fenced '#' does not close a span"
WN6="$S/wn6.md"
cat > "$WN6" <<'EOF'
<<! CTX-PREAMBLE >>

```
# not a heading — inside a fence
```

<<#1 below the fence>>

Sub Section
-----------

<<#2 under a setext-looking underline>>

# Real H1

<<#3 after a real h1>>
EOF
snap "$WN6"
scan "$WN6" > "$S/out6.json" || bad "scan exited non-zero"
eq "a fenced '#' line does not close the span" "CTX-PREAMBLE" \
  "$(jget "$S/out6.json" '",".join(c["text"] for p in d["placeholders"] if p["id"]==1 for c in p["context_chain"])')"
eq "a setext underline is NOT a heading, so the span still reaches #2" "CTX-PREAMBLE" \
  "$(jget "$S/out6.json" '",".join(c["text"] for p in d["placeholders"] if p["id"]==2 for c in p["context_chain"])')"
eq "no heading is recorded above a preamble block" "None" \
  "$(jget "$S/out6.json" 'str(d["context_blocks"][0]["source_heading"])')"
eq "the preamble block is level 0 (global, spans to EOF)" 0 \
  "$(jget "$S/out6.json" 'd["context_blocks"][0]["level"]')"
eq "a real ATX h1 does NOT close a level-0 preamble span" "CTX-PREAMBLE" \
  "$(jget "$S/out6.json" '",".join(c["text"] for p in d["placeholders"] if p["id"]==3 for c in p["context_chain"])')"

echo "--- 7c2: YAML frontmatter never parses as a heading"
WN8="$S/wn8.md"
cat > "$WN8" <<'EOF'
---
title: Study
version: 3
---

<<! GLOBAL-CTX >>

# Section

<<#1 do the thing>>
EOF
snap "$WN8"
scan "$WN8" > "$S/out8.json" || bad "scan exited non-zero"
eq "#1 still inherits the pre-heading global block" "GLOBAL-CTX" \
  "$(jget "$S/out8.json" '",".join(c["text"] for p in d["placeholders"] if p["id"]==1 for c in p["context_chain"])')"
eq "only the ATX '# Section' is a heading" "['Section']" \
  "$(jget "$S/out8.json" 'sorted(h for h in ({b["source_heading"] for b in d["context_blocks"]} | {p["section"] for p in d["placeholders"]}) if h)')"

echo "--- 7c3: a '#' line inside a placeholder body is not a heading"
WN9="$S/wn9.md"
cat > "$WN9" <<'EOF'
## S1

<<! SEC-CTX >>

<<#1 do this:
# step one
then that>>

<<#2 later task>>
EOF
snap "$WN9"
scan "$WN9" > "$S/out9.json" || bad "scan exited non-zero"
eq "#2 still inherits the section block below the multi-line body" "SEC-CTX" \
  "$(jget "$S/out9.json" '",".join(c["text"] for p in d["placeholders"] if p["id"]==2 for c in p["context_chain"])')"
eq "#1 itself is unaffected" "SEC-CTX" \
  "$(jget "$S/out9.json" '",".join(c["text"] for p in d["placeholders"] if p["id"]==1 for c in p["context_chain"])')"
eq "both placeholders are scoped to S1" "S1,S1" \
  "$(jget "$S/out9.json" '",".join(str(p["section"]) for p in d["placeholders"])')"

echo "--- 7d: @memory / @run are mutually exclusive along the chain"
WN7="$S/wn7.md"
printf '# D\n\n<<! @memory answer from the store >>\n\n<<#1 @run submit it anyway>>\n\n<<#2 plain>>\n' > "$WN7"
snap "$WN7"
scan "$WN7" > "$S/out7.json" || bad "scan exited non-zero"
eq "#1 own @run evicts the inherited @memory" "run" \
  "$(jget "$S/out7.json" '",".join(sorted([p["directives"] for p in d["placeholders"] if p["id"]==1][0]))')"
eq "#2 still inherits @memory" "memory" \
  "$(jget "$S/out7.json" '",".join(sorted([p["directives"] for p in d["placeholders"] if p["id"]==2][0]))')"

echo "--- 7e: a duplicate stamped id is an error, never a silent pick"
printf '# Dup\n\n<<#1 first>>\n\n<<#1 second>>\n' > "$S/dup.md"
scan "$S/dup.md" --id 1 >/dev/null 2>&1; eq "duplicate --id exits 2" 2 "$?"
dup_err=$(scan "$S/dup.md" --id 1 2>&1 >/dev/null)
check "error names the uniqueness rule" grep -q 'unique' <<<"$dup_err"
scan "$S/dup.md" > "$S/outdup.json" || bad "scan exited non-zero"
eq "the full report flags the collision in duplicate_ids" "[1]" \
  "$(jget "$S/outdup.json" 'd["duplicate_ids"]')"
eq "a clean worknote reports no duplicates" "[]" \
  "$(jget "$S/out1.json" 'd["duplicate_ids"]')"

echo "--- 7f: context-drift is only computed for a CLAIMED marker"
WN10="$S/wn10.md"
printf '# Pending\n\n<<! NEW-CTX-GGG >>\n\n<<#1 not claimed yet>>\n' > "$WN10"
MEM10="$S/mem10"; mkdir -p "$MEM10/tasks"
printf '## Attempts\n### Attempt 1 — 2026-07-02 10:00\n- context: OLD-CTX-HHH\n' > "$MEM10/tasks/task-1.md"
snap "$WN10"; snap "$MEM10"
scan "$WN10" --memory "$MEM10" > "$S/out10.json" || bad "scan exited non-zero"
eq "a stale task file does not make a pending placeholder drift" "None" \
  "$(jget "$S/out10.json" 'str([p["context_drift"] for p in d["placeholders"] if p["id"]==1][0])')"

echo "--- table format"
scan "$WN4" --memory "$MEM4" --format table > "$S/table.txt" || bad "table scan exited non-zero"
check "table has the id · state · owner · job · age · ctx header" \
  grep -Eq '^id +· *state +· *owner +· *job +· *age +· *ctx$' "$S/table.txt"
check "table lists the running markers" grep -q '#1 · running' "$S/table.txt"

echo "--- usage errors exit 2"
scan "$S/nope.md" >/dev/null 2>&1; eq "missing worknote exits 2" 2 "$?"
scan "$WN4" --id 99 >/dev/null 2>&1; eq "unknown --id exits 2" 2 "$?"

# ---------------------------------------------------------------------------
# 8 — read-only: nothing under the scratch fixtures changed.
# ---------------------------------------------------------------------------
echo "--- 8: read-only guarantee"
# Re-scan every fixture, then diff the whole pre-scan snapshot tree: content, file set,
# and any new file the script might have dropped beside a fixture.
scan "$WN1" >/dev/null; scan "$WN1" --id 2 >/dev/null
scan "$WN2" >/dev/null
scan "$WN3" --memory "$MEM3" >/dev/null
scan "$WN4" --memory "$MEM4" --format table >/dev/null
scan "$WN5" --memory "$MEM5" >/dev/null
scan "$WN6" >/dev/null; scan "$WN7" >/dev/null
scan "$WN8" >/dev/null; scan "$WN9" >/dev/null
scan "$WN10" --memory "$MEM10" >/dev/null
for f in wn1.md wn2.md wn3.md wn4.md wn5.md wn6.md wn7.md wn8.md wn9.md wn10.md \
         mem3 mem4 mem5 mem10; do
  check "$f byte-identical to its PRE-scan snapshot" diff -r "$SNAP/$f" "$S/$f"
done
# No stray file appeared next to the worknotes (the script must create nothing).
eq "no new files in the scratch fixture set" \
  "$(cd "$SNAP" && ls | tr '\n' ' ')" \
  "$(cd "$S" && ls | grep -vE '^(out[0-9a-z]*\.json|table\.txt|dup\.md|\.snapshot)$' | tr '\n' ' ')"

echo
if [ "$fails" -eq 0 ]; then
  echo "ALL OK — 0 failures"
else
  echo "FAILURES: $fails"
fi
exit $(( fails > 0 ))
