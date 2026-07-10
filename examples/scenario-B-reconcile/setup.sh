#!/usr/bin/env bash
# Prepare scenario-B-reconcile for an e2e or manual run.
#
# Idempotent. Mirrors `research-memory link` for the workdir, resets the mock scheduler, then
# PRE-SEEDS live job state so the pre-stamped markers resolve to the intended reconciliation
# states (running / unknown-stale / finished / orphaned) WITHOUT first running Mode A.
# The symlink and info/exclude entry are LOCAL state, never committed (also in repo .gitignore).
set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEM_DIR="$SCENARIO_DIR/Reconcile.memory"
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

# Fresh scheduler state, then seed the live jobs the markers/ledger reference.
MOCKJOB_STATE_DIR="$STATE_DIR" "$SCENARIO_DIR/../bin/mockjob" reset
mkdir -p "$STATE_DIR/jobs"
# Next real submit id = mock-0010 (max seeded id is mock-0009).
echo 9 > "$STATE_DIR/seq"
seed_job mock-0001 hang-running "sweep dp=2"              # -> running   (control)
seed_job mock-0006 fast-ok      "sweep dp=64" "throughput=1400.0 tok/s"  # -> finished (done-but-unwritten)
seed_job mock-0009 hang-running "sweep dp=128"            # -> running   (orphaned-job, no marker)
# Deliberately NO mock-0002 state file -> status resolves `unknown` (stale-claim).
# Deliberately NO mock-0003 (marker is job=pending, never submitted -> stale-claim).

echo "scenario-B-reconcile ready (pre-seeded markers + ledger)."
echo "  worknote: $SCENARIO_DIR/Reconcile.md"
echo "  memory:   $MEM_DIR"
echo "  seeded jobs: mock-0001(running) mock-0006(finished) mock-0009(running,orphan); mock-0002 unknown; mock-0003 pending"
echo "Pass 1 (read-only): /worknote-orchestrate $SCENARIO_DIR/Reconcile.md status"
echo "Pass 2 (planning):  /worknote-orchestrate $SCENARIO_DIR/Reconcile.md"
