#!/usr/bin/env python3
"""Record an asciicast (v2) of a scripted taskbay session: python3 demo/record.py [out.cast]

Neovim runs the plugin's minimal test config in a detached tmux pane, in a throwaway
repository, with the offline scripted agent from tests/fixtures; keys are typed
through tmux and every screen change is saved as a frame. Needs tmux and snacks.nvim
(TASKBAY_SNACKS, else lazy.nvim's checkout)."""
import json, os, shutil, subprocess, sys, tempfile, threading, time
from pathlib import Path

PLUGIN = Path(__file__).resolve().parents[1]
OUT = Path(sys.argv[1] if len(sys.argv) > 1 else PLUGIN / "demo/taskbay.cast").resolve()
W, H = 120, 34
tmp = Path(tempfile.mkdtemp(prefix="taskbay-demo-"))
repo, sock = tmp / "project", str(tmp / "tmux.sock")

def sh(*argv, cwd=repo, **kw):
    return subprocess.run(argv, cwd=cwd, check=True, text=True, capture_output=True, **kw).stdout

repo.mkdir()
sh("git", "init", "-q", "-b", "main")
sh("git", "config", "user.name", "Demo"); sh("git", "config", "user.email", "demo@example.invalid")
(repo / "README.md").write_text("# Project\n\nA tiny greeting library.\n")
(repo / "app.py").write_text("def greet(name):\n    return f'Hello, {name}!'\n")
sh("git", "add", "."); sh("git", "commit", "-qm", "Initial")
(tmp / "bin").mkdir()
(tmp / "bin/pi").write_text(f"#!/bin/sh\nexec python3 {PLUGIN}/tests/fixtures/pi_agent.py \"$@\"\n")
(tmp / "bin/pi").chmod(0o755)
(tmp / "data/nvim").mkdir(parents=True)
(tmp / "data/nvim/lazy").mkdir()
snacks = os.environ.get("TASKBAY_SNACKS", str(Path.home() / ".local/share/nvim/lazy/snacks.nvim"))
(tmp / "data/nvim/lazy/snacks.nvim").symlink_to(snacks)
(tmp / "init.lua").write_text(f"dofile({json.dumps(str(PLUGIN / 'tests/minimal_init.lua'))})\n"
                              "vim.o.termguicolors = true\nvim.cmd.colorscheme('retrobox')\n"
                              f"require('taskbay').setup({{ pi = {{ cmd = {json.dumps(str(tmp / 'bin/pi'))} }} }})\n")
release = tmp / "release"
env = {"PATH": f"{tmp}/bin:" + os.environ["PATH"], "XDG_DATA_HOME": f"{tmp}/data", "XDG_STATE_HOME": f"{tmp}/state",
       "XDG_CACHE_HOME": f"{tmp}/cache", "PI_E2E_LOG": f"{tmp}/agents.jsonl", "PI_E2E_RELEASE": str(release),
       "TERM": "tmux-256color", "COLORTERM": "truecolor", "LANG": "en_US.UTF-8"}
envargs = sum((["-e", f"{k}={v}"] for k, v in env.items()), [])

def tmux(*args): return subprocess.run(["tmux", "-S", sock, *args], text=True, capture_output=True).stdout
subprocess.run(["tmux", "-S", sock, "-f", "/dev/null", "new-session", "-d", "-x", str(W), "-y", str(H), *envargs,
                "-c", str(repo), f"nvim -i NONE -u {tmp}/init.lua README.md"], check=True)
tmux("set", "-g", "status", "off"); tmux("set", "-g", "escape-time", "0")
tmux("set", "-g", "default-terminal", "tmux-256color"); tmux("set", "-ga", "terminal-overrides", ",*:Tc")

frames, start, stop = [], time.time(), threading.Event()
def capture():
    last = None
    while not stop.is_set():
        screen = tmux("capture-pane", "-p", "-e", "-N")
        cur = tmux("display", "-p", "#{cursor_x} #{cursor_y}").split()
        if screen and len(cur) == 2:
            text = "\x1b[H\x1b[2J" + "\r\n".join(screen.rstrip("\n").split("\n")) \
                + f"\x1b[{int(cur[1]) + 1};{int(cur[0]) + 1}H"
            if text != last:
                frames.append([round(time.time() - start, 3), "o", text]); last = text
        time.sleep(0.08)
threading.Thread(target=capture, daemon=True).start()

def keys(*k, pause=0.6): tmux("send-keys", *k); time.sleep(pause)
def type_(text, cps=22):
    for ch in text: tmux("send-keys", "-l", ch); time.sleep(1 / cps)
def wait(s): time.sleep(s)
def until(text, timeout=30):
    """Wait until the screen shows text (startup and floats take a variable time)."""
    deadline = time.time() + timeout
    while text not in tmux("capture-pane", "-p"):
        if time.time() > deadline: sys.exit(f"demo: timed out waiting for {text!r}")
        time.sleep(0.1)
    time.sleep(0.3)

until("A tiny greeting library"); wait(1)
# 1. Write a task: Space a n opens a blank Markdown task.
keys("Space", "a", "n", pause=0); until("New task")
type_("Add a farewell function"); keys("Escape", "j", "o", pause=0.2)
type_("Add farewell(name) next to greet()."); keys("Enter", "Escape", "G", "A", pause=0.3)
type_("write farewell()"); keys("Enter", pause=0.2); type_("- [ ] add a test"); keys("Escape", pause=0.4); type_(":write"); keys("Enter", pause=1.5)
keys("Space", "a", "n", pause=0); until("New task")
type_("Add greeting tests"); keys("Escape", "j", "o", pause=0.2)
type_("Cover greet() with pytest."); keys("Enter", "Escape", "G", "A", pause=0.2); type_("test greet()"); keys("Escape", pause=0.4); type_(":write"); keys("Enter", pause=1.5)
# 2. The panel is the hub.
keys("Space", "a", "w", pause=0); until("Task Workspaces"); wait(2)
keys("?", pause=3.5); keys("Escape", pause=1)
# 3. Start both agents; each gets its own worktree, branch and tab.
keys("p", pause=3)
keys("C-\\", "C-n", pause=0.3); keys("Space", "a", "w", pause=1.5)
keys("j", pause=0.8); keys("p", pause=3)
keys("C-\\", "C-n", pause=0.3); keys("Space", "a", "w", pause=3)
keys("Escape", pause=0.5)
# 4. The agents finish; the panel shows who waits for review.
release.write_text("")
wait(2.5)
keys("C-\\", "C-n", pause=0.3); keys("Space", "a", "w", pause=3)
# 5. Review task 1's diff, then finish (commit + merge).
keys("d", pause=4.5); keys("Escape", "Escape", pause=1.5)
keys("Space", "a", "w", pause=1.5); keys("m", pause=3); keys("Down", pause=0.8); keys("Enter", pause=3)
keys("Space", "a", "w", pause=3.5)
stop.set(); time.sleep(0.2)
tmux("kill-server")
header = {"version": 2, "width": W, "height": H, "timestamp": int(start), "title": "taskbay demo",
          "env": {"TERM": "xterm-256color"}}
OUT.write_text(json.dumps(header) + "\n" + "".join(json.dumps(f) + "\n" for f in frames))
shutil.rmtree(tmp, ignore_errors=True)
print(f"{OUT}: {len(frames)} frames, {frames[-1][0]:.0f}s")
