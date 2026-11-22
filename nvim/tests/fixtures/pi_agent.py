#!/usr/bin/env python3
"""Scripted pi-agent stand-in for end-to-end tests: no network or model calls.

It behaves like pi from the editor's point of view: it reads the attached task,
reports lifecycle snapshots through NVIM_PI_STATUS, "works" until the test
releases it, edits its own worktree, settles, and then accepts terminal input.
"""
import json
import os
from pathlib import Path
import signal
import sys
import time
import tty

status = Path(os.environ["NVIM_PI_STATUS"])
run = os.environ["NVIM_PI_RUN"]
log = Path(os.environ["PI_E2E_LOG"])
release = os.environ.get("PI_E2E_RELEASE")
args = sys.argv[1:]
resumed = "--session" in args
session = args[args.index("--session-id") + 1] if "--session-id" in args else None
session_file = Path(args[args.index("--session") + 1]) if resumed else status.parent / "session.jsonl"
if resumed:
    session = json.loads(session_file.read_text().splitlines()[0])["id"]
else:
    session_file.write_text(json.dumps({"type": "session", "cwd": os.getcwd(), "id": session}) + "\n")
attachment = next((Path(arg[1:]) for arg in args if arg.startswith("@")), None)
prompt = attachment.read_text() if attachment else ""
title = prompt.splitlines()[0] if prompt else ""
sequence = 0


def publish(activity, outcome="unknown"):
    global sequence
    sequence += 1
    temporary = status.with_name(f"{status.name}.{os.getpid()}.tmp")
    temporary.write_text(json.dumps({
        "version": 1, "run": run, "sequence": sequence, "cwd": os.getcwd(),
        "session": session, "session_file": str(session_file),
        "activity": activity, "outcome": outcome, "model": "e2e/scripted-agent",
    }))
    temporary.replace(status)


def record(event, **fields):
    with log.open("a") as output:
        output.write(json.dumps({"event": event, "pid": os.getpid(), "run": run, "cwd": os.getcwd(),
                                 "resumed": resumed, "time": time.time(), **fields}) + "\n")


signal.signal(signal.SIGTERM, lambda *_: (record("stopped"), sys.exit(0)))
signal.signal(signal.SIGHUP, lambda *_: (record("stopped"), sys.exit(0)))
record("started", title=title, prompt=prompt, args=args)
print(f"scripted pi: {'resumed ' + session if resumed else title}", flush=True)
publish("idle")
if prompt:
    publish("working")
    while release and not Path(release).exists():
        time.sleep(0.02)
    if "[no changes]" not in prompt:
        Path("AGENT_RESULT.md").write_text(f"Implemented by scripted pi\n\n{title}\n")
    record("finished", title=title)
    print("scripted pi: task implemented, waiting for review", flush=True)
    publish("idle", "success")
if os.isatty(0):
    tty.setraw(0)  # like pi's TUI: receive pastes without waiting for a newline
while True:
    data = os.read(0, 4096)
    if not data:
        time.sleep(0.01)
        continue
    with (status.parent / "paste.txt").open("ab") as output:
        output.write(data)
