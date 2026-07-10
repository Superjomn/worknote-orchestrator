#!/usr/bin/env bash
# Prepare scenario-C-directives for an e2e or manual run.
#
# Idempotent. Mirrors `research-memory link` for EACH participating workdir (two @dir: targets
# plus the default invocation workdir), then resets the mock scheduler. The symlinks and the
# info/exclude entries are LOCAL workflow state and must never be committed (also covered by the
# repo .gitignore as a safety net). All three workdirs share ONE memory store.
set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEM_DIR="$SCENARIO_DIR/Directives.memory"

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

# Link all three participating workdirs to the SAME Directives.memory store.
link_workdir "$SCENARIO_DIR/workdir-alpha"
link_workdir "$SCENARIO_DIR/workdir-beta"
link_workdir "$SCENARIO_DIR/workdir"

# Reset the mock scheduler state for this scenario (empty ledger — nothing pre-seeded for C).
MOCKJOB_STATE_DIR="$MEM_DIR/.mockjob" "$SCENARIO_DIR/../bin/mockjob" reset

echo "scenario-C-directives ready."
echo "  worknote:      $SCENARIO_DIR/Directives.md"
echo "  memory:        $MEM_DIR  (shared by all workdirs)"
echo "  workdir-alpha: $SCENARIO_DIR/workdir-alpha  (research-memory -> Directives.memory)"
echo "  workdir-beta:  $SCENARIO_DIR/workdir-beta   (research-memory -> Directives.memory)"
echo "  workdir:       $SCENARIO_DIR/workdir        (research-memory -> Directives.memory)"
echo "@dir: base (resolve repo-relative directive paths against this):"
echo "  $(git -C "$SCENARIO_DIR" rev-parse --show-toplevel)"
echo "Run:  /worknote-orchestrate $SCENARIO_DIR/Directives.md"
