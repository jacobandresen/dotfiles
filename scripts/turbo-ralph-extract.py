#!/usr/bin/env python3
"""
Salvage a ralph iteration log when the model emitted fenced code blocks
instead of using tools.

Rules:
  - A fenced block ```<lang> ... ``` becomes a file iff its first content
    line is a path-comment matching one of:
        // path/to/file
        # path/to/file
        <!-- path/to/file -->
        /* path/to/file */
    The path must be relative (no leading /) and must not escape via "..".
  - Bash blocks (```bash / ```sh) are printed. With --run they are
    executed via /bin/sh after a confirmation prompt (skip with --yes).
  - Existing files are not overwritten unless --force.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

FENCE = re.compile(r"^```([A-Za-z0-9_+-]*)\s*$")
PATH_COMMENT = re.compile(
    r"""^\s*(?:
            //\s*(?P<a>\S+) |
            \#\s*(?P<b>\S+) |
            <!--\s*(?P<c>\S+)\s*--> |
            /\*\s*(?P<d>\S+)\s*\*/
        )\s*$""",
    re.VERBOSE,
)


def parse_blocks(text):
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        m = FENCE.match(lines[i])
        if not m:
            i += 1
            continue
        lang = m.group(1).lower()
        body = []
        i += 1
        while i < len(lines) and not FENCE.match(lines[i]):
            body.append(lines[i])
            i += 1
        if i < len(lines):
            i += 1  # consume closing fence
        yield lang, body


def extract_path(body):
    if not body:
        return None
    m = PATH_COMMENT.match(body[0])
    if not m:
        return None
    p = next(v for v in m.groupdict().values() if v)
    if p.startswith("/") or ".." in Path(p).parts:
        return None
    if "/" not in p and "." not in p:  # avoid matching plain words
        return None
    return p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log", type=Path)
    ap.add_argument("--root", type=Path, default=Path.cwd(),
                    help="directory to materialize files under")
    ap.add_argument("--run", action="store_true",
                    help="execute bash/sh blocks")
    ap.add_argument("--yes", action="store_true",
                    help="skip confirmation for --run")
    ap.add_argument("--force", action="store_true",
                    help="overwrite existing files")
    args = ap.parse_args()

    text = args.log.read_text()
    files = []
    scripts = []
    for lang, body in parse_blocks(text):
        path = extract_path(body)
        if path:
            files.append((path, "\n".join(body[1:]) + "\n"))
        elif lang in {"bash", "sh", "shell"}:
            scripts.append("\n".join(body))

    print(f"[extract] {len(files)} file block(s), {len(scripts)} shell block(s)")
    for path, content in files:
        dest = args.root / path
        if dest.exists() and not args.force:
            print(f"  skip  {path} (exists; use --force)")
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(content)
        print(f"  wrote {path} ({len(content)} bytes)")

    for idx, script in enumerate(scripts, 1):
        print(f"\n--- shell block {idx} ---\n{script}\n--- end ---")
        if not args.run:
            continue
        if not args.yes:
            ans = input(f"run shell block {idx}? [y/N] ").strip().lower()
            if ans != "y":
                print("  skipped")
                continue
        r = subprocess.run(script, shell=True, cwd=args.root)
        print(f"  exit={r.returncode}")


if __name__ == "__main__":
    main()
