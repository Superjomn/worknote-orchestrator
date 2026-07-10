#!/usr/bin/env bash
# Restore scenario-D-human-edit to its committed seed after a run (and the mutate) changed it.
#
# The git-tracked version of every fixture (worknote with its 3 original markers + seeded memory
# incl. task-3.md) IS the canonical seed, so a checkout is the reset. Also drops untracked run
# artifacts and any UNTRACKED task files created during a run (seeded task-3.md is tracked).
set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCENARIO_DIR" rev-parse --show-toplevel)"

git -C "$REPO_ROOT" checkout -- "examples/scenario-D-human-edit" 2>/dev/null || true
git -C "$REPO_ROOT" clean -fq -- "examples/scenario-D-human-edit/HumanEdit.memory/tasks" 2>/dev/null || true

rm -f "$SCENARIO_DIR/workdir/research-memory"
rm -rf "$SCENARIO_DIR/HumanEdit.memory/.mockjob"

echo "scenario-D-human-edit reset to committed seed (3 original RUNNING markers restored)."
