#!/usr/bin/env bash
# Restore scenario-A-fanout to its committed seed state after a run mutated it.
#
# The git-tracked version of every fixture IS the canonical seed, so a checkout is the reset.
# Also wipes the (untracked) mock-scheduler state and the (untracked) per-workdir symlink.
set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCENARIO_DIR" rev-parse --show-toplevel)"

# Restore all tracked fixture files (worknote + seeded memory) to their committed state.
git -C "$REPO_ROOT" checkout -- "examples/scenario-A-fanout" 2>/dev/null || true

# Remove untracked run artifacts.
rm -f "$SCENARIO_DIR/workdir/research-memory"
rm -rf "$SCENARIO_DIR/Fanout.memory/.mockjob"
# Drop any task files created during a run (none are seeded for A).
find "$SCENARIO_DIR/Fanout.memory/tasks" -name 'task-*.md' -delete 2>/dev/null || true

echo "scenario-A-fanout reset to committed seed."
