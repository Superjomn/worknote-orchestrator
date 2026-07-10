#!/usr/bin/env bash
# Prepare scenario-D-human-edit for a TWO-PHASE run.
#
# Idempotent. Mirrors `research-memory link` for the workdir, resets the mock scheduler, then
# PRE-SEEDS three live jobs so the three RUNNING markers persist across the human-edit window.
# The symlink and info/exclude entry are LOCAL state, never committed (also in repo .gitignore).
#
# Flow:  ./setup.sh  ->  run PHASE 1  ->  ./mutate.sh (the human edit)  ->  run PHASE 2
set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEM_DIR="$SCENARIO_DIR/HumanEdit.memory"
STATE_DIR="$MEM_DIR/.mockjob"

link_workdir() {
  local wd="$1"
  mkdir -p "$wd"
  rm -f "$wd/research-memory"
  ln -sfn "$MEM_DIR" "$wd/research-memory"
  local exclude
  exclude="$(git -C "$wd" rev-parse --git-path info/exclude)"
  case "$exclude" in
    /*) : ;;
    *) exclude="$(cd "$wd" && cd "$(dirname "$exclude")" && pwd)/$(basename "$exclude")" ;;
  esac
  mkdir -p "$(dirname "$exclude")"
  touch "$exclude"
  grep -qxF "research-memory" "$exclude" || echo "research-memory" >> "$exclude"
}

seed_job() {
  # seed_job <jobid> <plan> <purpose> [metric]
  local id="$1" plan="$2" purpose="$3" metric="${4:-throughput=1234.5 tok/s}"
  python3 - "$STATE_DIR" "$id" "$plan" "$purpose" "$metric" <<'PY'
import json, sys, pathlib
state, jid, plan, purpose, metric = sys.argv[1:6]
jobs = pathlib.Path(state) / "jobs"
jobs.mkdir(parents=True, exist_ok=True)
(jobs / f"{jid}.json").write_text(json.dumps({
    "id": jid, "purpose": purpose, "plan": plan, "metric": metric,
    "submitted_at": "2026-07-09 09:00:00", "result": None,
}, indent=2))
PY
}

link_workdir "$SCENARIO_DIR/workdir"

MOCKJOB_STATE_DIR="$STATE_DIR" "$SCENARIO_DIR/../bin/mockjob" reset
mkdir -p "$STATE_DIR/jobs"
# Next real submit id = mock-0004 (e.g. the superseded #2 re-dispatch).
echo 3 > "$STATE_DIR/seq"
seed_job mock-0001 hang-running "sweep dp=2"                              # -> running (persists; cancelled between phases)
seed_job mock-0002 hang-running "sweep dp=4"                              # -> running (persists; superseded between phases)
seed_job mock-0003 fast-ok      "sweep dp=8" "throughput=1250.0 tok/s"    # -> finished (lost-result: marker deleted post-finish)

echo "scenario-D-human-edit ready (3 live RUNNING markers seeded)."
echo "  worknote: $SCENARIO_DIR/HumanEdit.md"
echo "  memory:   $MEM_DIR"
echo "  jobs: mock-0001(running) mock-0002(running) mock-0003(finished)"
echo
echo "PHASE 1:  /worknote-orchestrate $SCENARIO_DIR/HumanEdit.md"
echo "THEN:     ./mutate.sh          # the human edit (cancel #1, supersede #2, delete #3 marker)"
echo "PHASE 2:  /worknote-orchestrate $SCENARIO_DIR/HumanEdit.md"
