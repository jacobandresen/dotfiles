#!/usr/bin/env python3
"""Local terminal fixture: no network or model calls."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

status = Path(os.environ["NVIM_PI_STATUS"])
args = sys.argv[1:]
session = args[args.index("--session-id") + 1] if "--session-id" in args else "resumed"
session_file = status.parent / "session.jsonl"
session_file.write_text(json.dumps({"type": "session", "cwd": os.getcwd(), "id": session}) + "\n")
if os.environ.get("NVIM_PI_TEST_CHILD"):
    child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(20)"])
    (status.parent / "child.pid").write_text(str(child.pid))
temporary = status.with_suffix(".tmp")
temporary.write_text(json.dumps({
    "version": 1, "run": os.environ["NVIM_PI_RUN"], "sequence": 1,
    "cwd": os.getcwd(), "session": session, "session_file": str(session_file),
    "activity": "idle", "model": os.environ["NVIM_PI_MODEL"],
}))
temporary.replace(status)
signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
while True:
    data = os.read(0, 4096)
    if not data:
        time.sleep(0.01)
        continue
    with (status.parent / "paste.txt").open("ab") as output:
        output.write(data)
