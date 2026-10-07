"""Shared host, process, and Ollama helpers for the dotfiles CLI."""

import json
import os
from pathlib import Path
import platform
import subprocess
import urllib.request


ROOT = Path(__file__).resolve().parents[1]
HOME = Path.home()


def run(*args, check=True, **kwargs):
    return subprocess.run(args, check=check, **kwargs)


def ram_profile():
    if platform.system() == "Darwin":
        total = int(run("sysctl", "-n", "hw.memsize", capture_output=True, text=True).stdout)
    else:
        line = next(line for line in Path("/proc/meminfo").read_text().splitlines() if line.startswith("MemTotal:"))
        total = int(line.split()[1]) * 1024
    gib = total // (1024 ** 3)
    return "32gb" if gib >= 24 else "16gb" if gib >= 12 else "8gb"


def coding_model():
    override = os.environ.get("DOTFILES_CODING_MODEL")
    if override:
        return override
    return "qwen3:4b" if platform.system() == "Darwin" else "qwen3-coder:30b" if ram_profile() == "32gb" else "qwen3:8b"


def ollama_api():
    host = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434")
    return host if host.startswith(("http://", "https://")) else f"http://{host}"


def api_json(path, data=None, timeout=3):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(ollama_api() + path, data=body)
    if body is not None:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return json.load(response)


def api_ready(path="/api/version"):
    try:
        api_json(path)
        return True
    except (OSError, ValueError):
        return False


def has_model(model):
    wanted = model if ":" in model else f"{model}:latest"
    result = run("ollama", "list", check=False, capture_output=True, text=True)
    return result.returncode == 0 and any(line.split()[0] == wanted for line in result.stdout.splitlines()[1:] if line.split())
