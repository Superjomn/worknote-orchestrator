#!/usr/bin/env bash
# Restore scenario-B-reconcile to its committed seed state after a run mutated it.
#
# The git-tracked version of every fixture (worknote + seeded memory incl. task-6.md) IS the
# canonical seed, so a checkout is the reset. Also wipes untracked run artifacts and any
# UNTRACKED task files created during a run (the seeded task-6.md is tracked and restored).
set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCENARIO_DIR" rev-parse --show-toplevel)"

# Restore tracked fixtures.
git -C "$REPO_ROOT" checkout -- "examples/scenario-B-reconcile" 2>/dev/null || true
# Remove untracked task files (e.g. task-5.md created when #5 re-activated); keep tracked ones.
git -C "$REPO_ROOT" clean -fq -- "examples/scenario-B-reconcile/Reconcile.memory/tasks" 2>/dev/null || true

# Remove untracked run artifacts.
rm -f "$SCENARIO_DIR/workdir/research-memory"
rm -rf "$SCENARIO_DIR/Reconcile.memory/.mockjob"

echo "scenario-B-reconcile reset to committed seed."
