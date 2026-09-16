#!/usr/bin/env python3
"""Reserve durable placeholder IDs without writing the human-owned worknote.

python3 wn_allocate.py <worknote> --memory <store> [--count N]

Creates task-file reservations with exclusive creation. Competing allocators cannot
return the same ID. Failed stamping or an interrupted allocation burns IDs, never
recycles them. The scanner remains read-only; its next_id is only a preview.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys

from wn_scan import scan


def allocate(worknote: str, memory: str, count: int = 1) -> list[int]:
    if count < 1:
        raise ValueError("count must be positive")
    store = Path(memory)
    if not store.is_dir():
        raise ValueError("memory store must already exist; run research-memory init")
    result = scan(worknote, memory)
    if result["duplicate_ids"]:
        raise ValueError("fix duplicate placeholder IDs before allocating")
    tasks = store / "tasks"
    tasks.mkdir(exist_ok=True)
    template = (Path(__file__).resolve().parents[2] / "research-memory" /
                "templates" / "task.md").read_text(encoding="utf-8")
    # Reservation is not execution: do not fabricate an Attempt or completed Outcome.
    template = template[:template.index("## Attempts")] + "## Attempts\n\n## Working notes\n\n## Outcome\n"
    pid = result["next_id"]
    reserved = []
    while len(reserved) < count:
        target = tasks / f"task-{pid}.md"
        try:
            # O_EXCL is the allocation operation: never overwrite an existing task.
            fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
        except FileExistsError:
            pid += 1
            continue
        # Keep the file even on failure: its name permanently reserves this ID.
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write("<!-- Reserved ID; initialize Brief before claiming. Never delete this reservation. -->\n")
            fh.write(template.replace("<id>", str(pid)).replace("<short title>", "Reserved"))
            fh.flush()
            os.fsync(fh.fileno())
        directory_fd = os.open(tasks, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
        reserved.append(pid)
        pid += 1
    return reserved


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("worknote")
    parser.add_argument("--memory", required=True)
    parser.add_argument("--count", type=int, default=1)
    args = parser.parse_args()
    try:
        ids = allocate(args.worknote, args.memory, args.count)
    except (OSError, ValueError) as exc:
        print(f"wn_allocate: {exc}", file=sys.stderr)
        return 2
    print(json.dumps({"reserved_ids": ids}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
