#!/usr/bin/env python3
"""wn_scan.py — read-only scanner for worknote placeholders and `<<! ... >>` context blocks.

    python3 wn_scan.py <worknote> [--memory <dir>] [--id N] [--format json|table]

Implements the mechanical rules of ../references/context-scanning.md:
scan-then-partition, marker parsing, context-block spans, ordered inheritance chains,
directive merging, `next_id` over three sources, and `context-drift`.

NEVER WRITES. Worknote mutations use exact edits with lifecycle ownership/intent guards.
Exit 0 on success, 2 on usage/parse error.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import re
import sys

PLACEHOLDER_RE = re.compile(r"<<[^<>]+?>>", re.DOTALL)
HEADING_RE = re.compile(r"^ {0,3}(#{1,6})\s+(.*?)\s*$")
FENCE_RE = re.compile(r"^ {0,3}(```+|~~~+)")
HEAD_ID_RE = re.compile(r"^(RUNNING|BLOCKED)?#(\d+)(?=\s|$)")
DIR_RE = re.compile(r"@dir:(\S+)")
TASK_FILE_RE = re.compile(r"^task-(\d+)\.md$")
BLOCKER_ID_RE = re.compile(r"BLOCKED#(\d+)")


def die(msg: str) -> None:
    print(f"wn_scan: {msg}", file=sys.stderr)
    sys.exit(2)


# --- parsing helpers ---------------------------------------------------------


def parse_directives(text: str) -> dict:
    """Extract the hint directives that may sit in a placeholder or a context block."""
    d = {}
    for m in DIR_RE.finditer(text):
        d["dir"] = m.group(1)
    for m in re.finditer(r"@(memory|run)\b", text):
        mode = m.group(1)
        d.pop("run" if mode == "memory" else "memory", None)
        d[mode] = True
    return d


def merge_directives(base: dict, new: dict) -> dict:
    """Later wins — and `@memory` / `@run` are mutually exclusive, so the later one evicts."""
    out = dict(base)
    out.update(new)
    if "memory" in new and "run" not in new:
        out.pop("run", None)
    if "run" in new and "memory" not in new:
        out.pop("memory", None)
    return out


def parse_marker(body: str) -> dict:
    """Parse a placeholder body into state / id / owner / job / since / task / Q / A."""
    body = body.strip()
    state = "pending"
    pid = None
    m = HEAD_ID_RE.match(body)
    if m:
        pid = int(m.group(2))
        state = m.group(1) or "pending"

    if state == "pending":
        # A pending placeholder has no marker fields: its whole body (minus the stamped
        # id) IS the task — that is what a dispatch pastes.
        return {
            "state": state,
            "id": pid,
            "owner": None,
            "attempt": None,
            "job": None,
            "since": None,
            "task": (body[m.end():] if m else body).strip(),
            "question": None,
            "answer": None,
        }

    # Fields live before `task:`; the free-text fields follow it.
    head, sep, tail = body.partition("task:")
    fields = {}
    for key in ("owner", "attempt", "job", "since"):
        fm = re.search(rf"\b{key}=(\S+)", head)
        if fm:
            fields[key] = fm.group(1)

    task = q = a = None
    blocker_format = None
    if sep and state == "RUNNING":
        # Q:/A: are ordinary task text unless the marker is BLOCKED.
        task = tail.strip()
    elif sep:
        rest = tail
        # New claims append single-line Q/A fields on separate lines. The last
        # Q line is metadata, preserving any literal Q: lines inside the task.
        task_part, qsep, qa = rest.rpartition("\nQ:")
        if qsep and fields.get("attempt"):
            blocker_format = "lines"
            task = task_part.strip()
            question_part, asep, answer_part = qa.partition("\nA:")
            if "\n" in question_part.strip() or (asep and "\n" in answer_part.strip()):
                # Old multiline metadata stays inspectable. Only guarded writes
                # require the unambiguous, single-line metadata encoding.
                blocker_format = "legacy"
            q = question_part.strip()
            a = answer_part.strip() if asep else None
        elif (qm := re.search(r"\bQ:", rest)):
            # Legacy inline markers remain readable, but cannot pass a write guard.
            blocker_format = "legacy"
            task = rest[: qm.start()].strip()
            rest = rest[qm.end():]
            am = re.search(r"\bA:", rest)
            if am:
                q = rest[: am.start()].strip()
                a = rest[am.end():].strip()
            else:
                q = rest.strip()
        else:
            task = rest.strip()

    return {
        "state": state,
        "id": pid,
        "owner": fields.get("owner"),
        "attempt": fields.get("attempt"),
        "job": fields.get("job"),
        "since": fields.get("since"),
        "task": task,
        "question": q,
        "answer": a,
        "blocker_format": blocker_format,
    }


def headings(lines: list[str], masked: set[int] | None = None) -> list[tuple[int, int, str]]:
    """(line_no, level, text) for every markdown heading, 1-based line numbers.

    ATX only (`#`..`######`, up to 3 leading spaces) — setext (`===` / `---` under a text
    line) is deliberately NOT recognized, so YAML frontmatter cannot masquerade as a
    heading. Lines inside a ``` / ~~~ fence and lines in `masked` (the lines a `<<...>>`
    match spans) are skipped for both the heading test and the fence toggle, so neither a
    code sample nor a placeholder's own text can close a context block's span.
    """
    masked = masked or set()
    out = []
    fence = None
    for i, ln in enumerate(lines, start=1):
        if i in masked:
            continue
        fm = FENCE_RE.match(ln)
        if fm:
            marker = fm.group(1)
            if fence is None:
                # Backtick info strings cannot themselves contain a backtick.
                if marker[0] != "`" or "`" not in ln[fm.end():]:
                    fence = marker
            elif (marker[0] == fence[0] and len(marker) >= len(fence)
                  and not ln[fm.end():].strip()):
                fence = None
            continue
        if fence is not None:
            continue
        m = HEADING_RE.match(ln)
        if m:
            out.append((i, len(m.group(1)), m.group(2)))
    return out


def enclosing_heading(hs, line: int):
    """Nearest heading at or above `line`, or None (preamble)."""
    found = None
    for h in hs:
        if h[0] <= line:
            found = h
        else:
            break
    return found


def span_end(hs, line: int, level: int, eof: int) -> int:
    """End line of the span: the line before the next heading of level <= `level`."""
    if level == 0:
        return eof
    for h in hs:
        if h[0] > line and h[1] <= level:
            return h[0] - 1
    return eof


def age_days(since: str | None) -> str:
    if not since:
        return "—"
    m = re.match(r"(\d{4})-(\d{2})-(\d{2})", since)
    if not m:
        return "—"
    try:
        d = datetime.date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
    except ValueError:
        return "—"
    return f"{(datetime.date.today() - d).days}d"


# --- memory-backed inputs ----------------------------------------------------


def memory_ids(memdir: str) -> tuple[int, int]:
    """max id from tasks/task-<id>.md filenames and from BLOCKED#<id> in blockers.md."""
    task_max = 0
    tasks_dir = os.path.join(memdir, "tasks")
    if os.path.isdir(tasks_dir):
        for name in os.listdir(tasks_dir):
            m = TASK_FILE_RE.match(name)
            if m:
                task_max = max(task_max, int(m.group(1)))
    blocker_max = 0
    bpath = os.path.join(memdir, "blockers.md")
    if os.path.isfile(bpath):
        with open(bpath, encoding="utf-8", errors="replace") as fh:
            for m in BLOCKER_ID_RE.finditer(fh.read()):
                blocker_max = max(blocker_max, int(m.group(1)))
    return task_max, blocker_max


def attempt_context(memdir: str, pid: int) -> str | None:
    """The `- context:` line of the LATEST `### Attempt N` in tasks/task-<id>.md."""
    path = os.path.join(memdir, "tasks", f"task-{pid}.md")
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    attempts = re.split(r"^###\s+Attempt\b", text, flags=re.M)
    if len(attempts) < 2:
        return None
    # Bound the last Attempt at the next heading, so a `context:` line in Working notes
    # or Outcome is never mistaken for the Attempt's recorded chain.
    last = re.split(r"^ {0,3}#{1,6}\s", attempts[-1], flags=re.M)[0]
    # Horizontal whitespace only: an empty context must not consume the next field.
    m = re.search(r"^-[ \t]*context:[ \t]*(.*?)[ \t]*$", last, flags=re.M)
    return m.group(1) if m else None


# --- core scan ---------------------------------------------------------------


def chain_text(chain: list[dict]) -> str:
    """Canonical serialization recorded as the task file's `context:` line: block texts
    joined by ` | `, outermost -> innermost; an empty chain is the literal `none`."""
    return " | ".join(" ".join(c["text"].split()) for c in chain) if chain else "none"


def same_chain(recorded: str, resolved: str) -> bool:
    """Whitespace-insensitive compare; an empty recorded value reads as `none`."""
    def norm(s: str) -> str:
        return " ".join(s.split()).strip() or "none"
    return norm(recorded) == norm(resolved)


def task_fingerprint(task: str | None, chain: list[dict], directives: dict) -> str:
    """Execution inputs only: moves and job updates do not invalidate an attempt.

    Keep block boundaries and exact task/context text, unlike the display-only ` | `
    serialization. A changed command's whitespace can be significant.
    """
    payload = [task, [c["text"] for c in chain], directives]
    return hashlib.sha256(json.dumps(payload, sort_keys=True,
                                     ensure_ascii=False).encode("utf-8")).hexdigest()


def verify_attempt(p: dict, attempt: str, owner: str, fingerprint: str) -> None:
    """Fail closed for legacy markers, takeover, cancellation, or changed intent."""
    if (p["state"] not in ("RUNNING", "BLOCKED") or not p["attempt"]
            or p["attempt"] != attempt or p["owner"] != owner):
        raise ValueError("attempt ownership changed; retain results in the old attempt only")
    if p["fingerprint"] != fingerprint:
        raise ValueError("task/context changed; retain results in the old attempt only")
    if p["state"] == "BLOCKED" and p["blocker_format"] != "lines":
        raise ValueError("legacy BLOCKED encoding requires reconciliation before publication")


def scan(path: str, memdir: str | None) -> dict:
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError as exc:
        die(f"cannot read worknote: {exc}")

    lines = text.split("\n")
    eof = len(lines)
    # Offset -> 1-based line number.
    starts = []
    pos = 0
    for ln in lines:
        starts.append(pos)
        pos += len(ln) + 1

    def line_of(offset: int) -> int:
        lo, hi = 0, len(starts) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if starts[mid] <= offset:
                lo = mid
            else:
                hi = mid - 1
        return lo + 1

    # Hide marker contents, preserving structural prefixes outside each match. Masking
    # whole lines would hide a real heading such as '# Results <<task>>'. Non-whitespace
    # padding also prevents text after a closing marker from becoming a fake heading.
    matches = list(PLACEHOLDER_RE.finditer(text))
    structural = []
    previous = 0
    for m in matches:
        structural.extend((text[previous:m.start()], re.sub(r"[^\n]", "x", m.group(0))))
        previous = m.end()
    structural.append(text[previous:])
    hs = [(line, level, HEADING_RE.match(lines[line - 1]).group(2))
          for line, level, _ in headings("".join(structural).split("\n"))]

    context_blocks: list[dict] = []
    placeholders: list[dict] = []
    worknote_max_id = 0

    for m in matches:
        raw = m.group(0)
        body = raw[2:-2]
        line = line_of(m.start())
        # Partition AFTER matching — body starting with `!` is a context block, never a task.
        if body.lstrip().startswith("!"):
            enc = enclosing_heading(hs, line)
            level = enc[1] if enc else 0
            block_text = body.lstrip()[1:].strip()
            context_blocks.append({
                "line": line,
                "text": block_text,
                "source_heading": enc[2] if enc else None,
                "level": level,
                "span": [line, span_end(hs, line, level, eof)],
                "directives": parse_directives(block_text),
            })
            continue

        info = parse_marker(body)
        if info["id"] is not None:
            worknote_max_id = max(worknote_max_id, info["id"])
        enc = enclosing_heading(hs, line)
        placeholders.append({
            "id": info["id"],
            "line": line,
            "state": info["state"],
            "owner": info["owner"],
            "attempt": info["attempt"],
            "job": info["job"],
            "since": info["since"],
            "task": info["task"],
            "question": info["question"],
            "answer": info["answer"],
            "blocker_format": info.get("blocker_format"),
            "body": body.strip(),
            "section": enc[2] if enc else None,
            "own_directives": parse_directives(info["task"] or ""),
        })

    # Chains: every context block whose span contains the placeholder's line,
    # ordered by the block's own line ascending = outermost -> innermost.
    for p in placeholders:
        chain = [b for b in context_blocks if b["span"][0] <= p["line"] <= b["span"][1]]
        chain.sort(key=lambda b: b["line"])
        merged: dict = {}
        for b in chain:
            merged = merge_directives(merged, b["directives"])
        merged = merge_directives(merged, p["own_directives"])
        p["context_chain"] = [
            {"line": b["line"], "source_heading": b["source_heading"], "text": b["text"]}
            for b in chain
        ]
        p["directives"] = merged
        p["effective_dir"] = merged.get("dir")
        p["fingerprint"] = task_fingerprint(p["task"], p["context_chain"], merged)
        p["context_drift"] = None
        # Drift only means something for a CLAIMED marker: a stale task file left by a
        # finished round must not make an unclaimed placeholder report drift.
        if memdir and p["id"] is not None and p["state"] in ("RUNNING", "BLOCKED"):
            recorded = attempt_context(memdir, p["id"])
            if recorded is not None:
                p["context_drift"] = not same_chain(recorded, chain_text(chain))

    task_max = blocker_max = 0
    if memdir:
        task_max, blocker_max = memory_ids(memdir)

    # `--id N` errors on a collision, but the full report is the one place a duplicate
    # would otherwise pass unnoticed — two `#1` rows and nothing saying so.
    seen: dict[int, int] = {}
    for p in placeholders:
        if p["id"] is not None:
            seen[p["id"]] = seen.get(p["id"], 0) + 1

    return {
        "worknote": os.path.abspath(path),
        "duplicate_ids": sorted(i for i, n in seen.items() if n > 1),
        "next_id": max(worknote_max_id, task_max, blocker_max) + 1,
        "next_id_sources": {
            "worknote_markers": worknote_max_id,
            "task_files": task_max,
            "blockers": blocker_max,
        },
        "context_blocks": [
            {k: b[k] for k in ("line", "text", "source_heading", "level", "span", "directives")}
            for b in context_blocks
        ],
        "placeholders": [
            {k: p[k] for k in (
                "id", "line", "state", "owner", "attempt", "fingerprint", "job", "since", "task", "question",
                "answer", "blocker_format", "body", "section", "context_chain", "effective_dir",
                "directives", "context_drift")}
            for p in placeholders
        ],
    }


def render_table(result: dict) -> str:
    rows = [("id", "state", "owner", "job", "age", "ctx")]
    for p in result["placeholders"]:
        state = p["state"].lower()
        if state == "blocked" and p["answer"]:
            state = "blocked+answered"
        rows.append((
            f"#{p['id']}" if p["id"] is not None else "—",
            state,
            p["owner"] or "—",
            p["job"] or "—",
            age_days(p["since"]),
            str(len(p["context_chain"])),
        ))
    widths = [max(len(r[i]) for r in rows) for i in range(6)]
    out = []
    for r in rows:
        out.append(" · ".join(r[i].ljust(widths[i]) for i in range(6)).rstrip())
    return "\n".join(out)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(add_help=True, description=__doc__)
    ap.add_argument("worknote")
    ap.add_argument("--memory", default=None, help="research-memory store dir")
    ap.add_argument("--id", type=int, default=None, help="emit only this placeholder")
    ap.add_argument("--format", choices=("json", "table"), default="json")
    ap.add_argument("--expect-attempt", help="guard a write using the dispatch attempt token")
    ap.add_argument("--expect-owner", help="guard a write using the dispatch owner")
    ap.add_argument("--expect-fingerprint", help="guard a write using the dispatch input hash")
    try:
        args = ap.parse_args(argv)
    except SystemExit as exc:  # --help exits 0; a usage error exits 2
        return 0 if exc.code in (0, None) else 2

    if not os.path.isfile(args.worknote):
        die(f"no such worknote: {args.worknote}")
    if args.memory and not os.path.isdir(args.memory):
        die(f"no such memory dir: {args.memory}")
    guards = (args.expect_attempt, args.expect_owner, args.expect_fingerprint)
    if any(v is not None for v in guards) and (not all(guards) or args.id is None):
        die("write guard requires --id and all three --expect-* arguments")

    result = scan(args.worknote, args.memory)

    if args.id is not None:
        match = [p for p in result["placeholders"] if p["id"] == args.id]
        if not match:
            die(f"no placeholder with id #{args.id}")
        if len(match) > 1:
            # A stamped id must resolve to exactly one placeholder — never guess which.
            die(f"id #{args.id} is stamped on {len(match)} placeholders "
                f"(lines {', '.join(str(p['line']) for p in match)}) — ids must be unique")
        if all(guards):
            verify_attempt(match[0], *guards)
        if args.format == "table":
            print(render_table({"placeholders": match}))
        else:
            print(json.dumps(match[0], indent=2))
        return 0

    if args.format == "table":
        print(render_table(result))
    else:
        print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except SystemExit:
        raise
    except Exception as exc:  # parse errors surface as exit 2, never a traceback dump
        die(str(exc))
