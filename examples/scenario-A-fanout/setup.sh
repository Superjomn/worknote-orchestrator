#!/usr/bin/env bash
# Prepare scenario-A-fanout for an e2e or manual run.
#
# Idempotent. Mirrors what `research-memory link` does per workdir, plus a mock-scheduler
# reset. Safe to re-run. The symlink and the info/exclude entry are LOCAL workflow state and
# must never be committed (they are also covered by the repo .gitignore as a safety net).
set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEM_DIR="$SCENARIO_DIR/Fanout.memory"

link_workdir() {
  local wd="$1"
  mkdir -p "$wd"
  # Fresh symlink to the single shared memory store at the fixed relative path.
  rm -f "$wd/research-memory"
  ln -sfn "$MEM_DIR" "$wd/research-memory"

  # Register the symlink in git info/exclude (NOT .gitignore) — mirrors research-memory link.
  local exclude
  exclude="$(git -C "$wd" rev-parse --git-path info/exclude)"
  # rev-parse prints a path relative to $wd; make it absolute for a stable append target.
  case "$exclude" in
    /*) : ;;
    *) exclude="$(cd "$wd" && cd "$(dirname "$exclude")" && pwd)/$(basename "$exclude")" ;;
  esac
  mkdir -p "$(dirname "$exclude")"
  touch "$exclude"
  grep -qxF "research-memory" "$exclude" || echo "research-memory" >> "$exclude"
}

link_workdir "$SCENARIO_DIR/workdir"

# Reset the mock scheduler state for this scenario (empty ledger — nothing pre-seeded for A).
MOCKJOB_STATE_DIR="$MEM_DIR/.mockjob" "$SCENARIO_DIR/../bin/mockjob" reset

echo "scenario-A-fanout ready."
echo "  worknote:   $SCENARIO_DIR/Fanout.md"
echo "  memory:     $MEM_DIR"
echo "  workdir:    $SCENARIO_DIR/workdir  (research-memory -> Fanout.memory)"
echo "Run:  /worknote-orchestrate $SCENARIO_DIR/Fanout.md"
