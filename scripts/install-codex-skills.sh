#!/usr/bin/env bash
# Install both sibling skills; Python 3 is also required by the skill helpers.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 - "$script_dir/../skills" "$@" <<'PY'
import argparse
import os
from pathlib import Path
import shutil
import sys

source = Path(sys.argv.pop(1)).resolve()
parser = argparse.ArgumentParser(description="Install both Codex skills without overwriting existing content.")
parser.add_argument('--target', default=os.environ.get('CODEX_SKILLS_DIR') or str(Path.home() / '.agents/skills'),
                    help='skills directory (default: CODEX_SKILLS_DIR or ~/.agents/skills)')
parser.add_argument('--copy', action='store_true', help='copy instead of symlinking; identical copies are left alone')
args = parser.parse_args()
target = Path(args.target).expanduser().absolute()


def snapshot(root):
    """Compare full trees by bytes/type, ignoring generated Python bytecode."""
    result = {}
    for base, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = [d for d in dirs if d != '__pycache__']
        for name in dirs + files:
            path = Path(base) / name
            key = str(path.relative_to(root))
            if path.is_symlink():
                result[key] = ('link', os.readlink(path))
            elif path.is_dir():
                result[key] = ('dir',)
            elif path.is_file():
                result[key] = ('file', path.read_bytes(), path.stat().st_mode & 0o111)
            else:
                raise ValueError(f'unsupported file type: {path}')
    return result


try:
    pending = []
    # Preflight both skills before creating anything, so conflicts do not leave
    # a half-installed pair. Existing paths are never removed or replaced.
    for name in ('research-memory', 'worknote-orchestrate'):
        src, dest = source / name, target / name
        if not (src / 'SKILL.md').is_file():
            raise ValueError(f'missing skill: {src}')
        if dest.is_symlink():
            if dest.resolve() != src:
                raise ValueError(f'refusing to overwrite: {dest}')
        elif dest.exists():
            if not (args.copy and dest.is_dir() and snapshot(src) == snapshot(dest)):
                raise ValueError(f'refusing to overwrite: {dest}')
        else:
            if dest.resolve().is_relative_to(src):
                raise ValueError(f'target cannot be inside source skill: {dest}')
            pending.append((src, dest))
    target.mkdir(parents=True, exist_ok=True)
    for src, dest in pending:
        if args.copy:
            shutil.copytree(src, dest, symlinks=True, ignore=shutil.ignore_patterns('__pycache__'))
        else:
            dest.symlink_to(src, target_is_directory=True)
    print(f'Skills ready in {target} ({"copy" if args.copy else "symlink"} mode; matching existing installs preserved).')
except (OSError, ValueError) as error:
    parser.exit(1, f'install-codex-skills: {error}\n')
PY
