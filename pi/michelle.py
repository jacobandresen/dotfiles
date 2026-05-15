#!/usr/bin/env python3
"""michelle — ollama management tool for the pi agent.

Author: Jacob Andresen <jacob.andresen@gmail.com>
"""

import argparse
import getpass
import json
import os
import platform
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

# ── constants ────────────────────────────────────────────────────────────────

DEFAULT_MODEL = "qwen3:8b"
IS_MACOS = platform.system() == "Darwin"

# Curated set of models that fit a 6 GB-VRAM / 16 GB-RAM box.
# Keys are the ollama id; values mirror the models.json schema.
KNOWN_MODELS: dict[str, dict] = {
    "qwen3:8b": {
        "_launch": True,
        "contextWindow": 131072,
        "id": "qwen3:8b",
        "input": ["text", "image"],
        "reasoning": True,
        "description": "General-purpose / agentic. Strong tool use and reasoning. Best default.",
    },
    "qwen2.5-coder:7b": {
        "contextWindow": 32768,
        "id": "qwen2.5-coder:7b",
        "input": ["text"],
        "description": "Code specialist. Better than qwen3 at diffs, edits, and completion.",
    },
    "gemma3:4b": {
        "contextWindow": 131072,
        "id": "gemma3:4b",
        "input": ["text", "image"],
        "description": "Small + fast fallback. Good for routing, classification, quick summaries.",
    },
}
OLLAMA_SRC = Path("/var/lib/ollama")
OLLAMA_DST = Path("/opt/ollama")
SETTINGS_PATH = Path(__file__).parent / "agent" / "settings.json"
MODELS_PATH = Path(__file__).parent / "agent" / "models.json"

# ── colors ───────────────────────────────────────────────────────────────────

_USE_COLOR = sys.stdout.isatty() and os.environ.get("NO_COLOR") is None

def _c(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if _USE_COLOR else text

def green(t: str) -> str: return _c("32", t)
def yellow(t: str) -> str: return _c("33", t)
def red(t: str) -> str:    return _c("31", t)
def cyan(t: str) -> str:   return _c("36", t)
def bold(t: str) -> str:   return _c("1", t)
def dim(t: str) -> str:    return _c("2", t)


def _table(headers: list[str], rows: list[list[str]]) -> None:
    all_rows = [headers] + rows
    widths = [max(len(r[i]) for r in all_rows) for i in range(len(headers))]
    sep = "  " + "-+-".join("-" * w for w in widths) + "  "
    header_row = "  " + " | ".join(bold(h.ljust(widths[i])) for i, h in enumerate(headers))
    print(header_row)
    print(dim(sep))
    for row in rows:
        print("  " + " | ".join(cell.ljust(widths[i] + (len(cell) - len(_strip_ansi(cell)))) for i, cell in enumerate(row)))


def _strip_ansi(s: str) -> str:
    return re.sub(r"\033\[[0-9;]*m", "", s)


# ── helpers ───────────────────────────────────────────────────────────────────


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True)


def die(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


# ── sudo helpers (used by move-storage) ──────────────────────────────────────


def sudo(password: str, *args: str) -> None:
    result = subprocess.run(
        ["sudo", "-S"] + list(args),
        input=password + "\n",
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        die(f"sudo {' '.join(args)}\n{result.stderr.strip()}")


def validate_password(password: str) -> None:
    result = subprocess.run(
        ["sudo", "-S", "true"],
        input=password + "\n",
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        die("wrong sudo password")


# ── ollama model helpers ──────────────────────────────────────────────────────


def get_installed_models() -> list[str]:
    result = run(["ollama", "list"])
    if result.returncode != 0:
        die(f"could not list ollama models\n{result.stderr.strip()}")
    lines = result.stdout.strip().splitlines()
    return [line.split()[0] for line in lines[1:] if line.split()]


def get_resident_models() -> list[str]:
    """Return the names of models currently loaded in ollama memory."""
    result = run(["ollama", "ps"])
    if result.returncode != 0:
        die(f"could not query ollama ps\n{result.stderr.strip()}")
    lines = result.stdout.strip().splitlines()
    return [line.split()[0] for line in lines[1:] if line.split()]


def pull_model(model: str) -> None:
    print(f"Pulling {model}...")
    result = subprocess.run(["ollama", "pull", model])
    if result.returncode != 0:
        die(f"failed to pull {model}")


# ── pi agent config helpers ───────────────────────────────────────────────────


def _read_default_model() -> str:
    if SETTINGS_PATH.exists():
        try:
            data = json.loads(SETTINGS_PATH.read_text())
            if isinstance(data.get("defaultModel"), str):
                return data["defaultModel"]
        except json.JSONDecodeError:
            pass
    return DEFAULT_MODEL


def _update_settings_default(model: str) -> None:
    if not SETTINGS_PATH.exists():
        print(f"WARNING: {SETTINGS_PATH} not found", file=sys.stderr)
        return
    data = json.loads(SETTINGS_PATH.read_text())
    if data.get("defaultModel") == model:
        print(f"settings.json: defaultModel='{model}' ✓")
        return
    print(f"settings.json: updating defaultModel -> '{model}'...")
    data["defaultModel"] = model
    SETTINGS_PATH.write_text(json.dumps(data, indent=2) + "\n")
    print("settings.json: updated ✓")


def _upsert_models_json(model: str) -> None:
    """Ensure models.json has an entry for `model`; add from KNOWN_MODELS if missing."""
    if not MODELS_PATH.exists():
        print(f"WARNING: {MODELS_PATH} not found", file=sys.stderr)
        return
    data = json.loads(MODELS_PATH.read_text())
    ollama = data.setdefault("providers", {}).setdefault("ollama", {})
    models = ollama.setdefault("models", [])
    if any(m.get("id") == model for m in models):
        print(f"models.json: '{model}' already present ✓")
        return
    entry = KNOWN_MODELS.get(model, {"id": model, "input": ["text"]})
    entry = {k: v for k, v in entry.items() if k != "description"}
    models.append(entry)
    MODELS_PATH.write_text(json.dumps(data, indent=2) + "\n")
    print(f"models.json: added '{model}' ✓")


# ── ollama HTTP helpers ───────────────────────────────────────────────────────


def ollama_host() -> str:
    return os.environ.get("OLLAMA_HOST", "http://localhost:11434").rstrip("/")


def load_ollama(model: str, keep_alive: str = "30m") -> None:
    """Send a tiny generation request to load `model` into memory."""
    host = ollama_host()
    print(f"Loading {model} on {host} (keep_alive={keep_alive})...")
    payload = json.dumps({
        "model": model,
        "prompt": "hi",
        "stream": False,
        "keep_alive": keep_alive,
    }).encode()
    req = urllib.request.Request(
        f"{host}/api/generate",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=600) as resp:
            resp.read()
    except urllib.error.URLError as e:
        die(f"failed to reach ollama at {host}: {e}")
    print(f"Done. {model} is resident for {keep_alive}.")


def unload_ollama(model: str) -> None:
    """Ask ollama to unload `model` from memory without removing it from disk."""
    host = ollama_host()
    print(f"Unloading {model} from {host}...")
    payload = json.dumps({
        "model": model,
        "keep_alive": 0,
    }).encode()
    req = urllib.request.Request(
        f"{host}/api/generate",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            resp.read()
    except urllib.error.URLError as e:
        die(f"failed to reach ollama at {host}: {e}")
    print(f"Done. {model} unloaded from memory (still installed).")


# ── commands ──────────────────────────────────────────────────────────────────


def cmd_move_storage(_args: argparse.Namespace) -> None:
    """Move ollama library to /opt/ollama and symlink back."""
    if IS_MACOS:
        die("move-storage is not supported on macOS (ollama stores data in ~/.ollama)")
    password = getpass.getpass("sudo password: ")
    validate_password(password)

    print("Stopping ollama...")
    sudo(password, "systemctl", "stop", "ollama")

    if OLLAMA_DST.exists():
        sudo(password, "systemctl", "start", "ollama")
        die(f"{OLLAMA_DST} already exists — aborting to avoid overwrite")

    print(f"Moving {OLLAMA_SRC} -> {OLLAMA_DST} ...")
    sudo(password, "mv", str(OLLAMA_SRC), str(OLLAMA_DST))

    print(f"Creating symlink {OLLAMA_SRC} -> {OLLAMA_DST} ...")
    sudo(password, "ln", "-s", str(OLLAMA_DST), str(OLLAMA_SRC))

    print("Starting ollama...")
    sudo(password, "systemctl", "start", "ollama")

    print("Done. Verify with: ollama list")


def cmd_load(args: argparse.Namespace) -> None:
    """Make `model` the sole resident model: pull if missing, unload others, load it."""
    model = args.model or _read_default_model()

    installed = get_installed_models()
    if model not in installed:
        pull_model(model)
    else:
        print(f"{model}: already installed ✓")

    _update_settings_default(model)
    _upsert_models_json(model)

    for m in get_resident_models():
        if m != model:
            unload_ollama(m)

    load_ollama(model, keep_alive=args.keep_alive)


def cmd_unload(args: argparse.Namespace) -> None:
    """Unload the default model from ollama memory without uninstalling it."""
    model = args.model or _read_default_model()
    unload_ollama(model)


def _model_status_marks(mid: str, installed: set[str], default: str) -> list[str]:
    marks = []
    if mid in installed:
        marks.append("installed")
    if mid == default:
        marks.append("default")
    return marks


def cmd_models(args: argparse.Namespace) -> None:
    """List the curated set of known models that fit a small GPU."""
    installed = set(get_installed_models())
    default = _read_default_model()

    if args.tsv:
        # Tab-separated: <display>\t<id> — for use as an fzf source.
        for mid, spec in KNOWN_MODELS.items():
            marks = _model_status_marks(mid, installed, default)
            ctx = f"{spec.get('contextWindow', 0) // 1024}k"
            suffix = f"  [{', '.join(marks)}]" if marks else ""
            print(f"{mid:<20} {ctx:>5}  {spec.get('description', '')}{suffix}\t{mid}")
        return

    print(bold("Curated models (fit ≤6 GB VRAM)"))
    rows = []
    for mid, spec in KNOWN_MODELS.items():
        marks = _model_status_marks(mid, installed, default)
        coloured = [green(m) if m == "installed" else cyan(m) for m in marks]
        ctx = f"{spec.get('contextWindow', 0) // 1024}k"
        caps = ", ".join(spec.get("input", []))
        if spec.get("reasoning"):
            caps += ", reasoning"
        rows.append([green(mid), cyan(ctx), caps, ", ".join(coloured)])
    _table(["Model", "Context", "Capabilities", "Status"], rows)
    print()


def cmd_model_info(args: argparse.Namespace) -> None:
    """Print a multi-line summary for a single curated model (preview for fzf)."""
    spec = KNOWN_MODELS.get(args.model)
    if spec is None:
        print(f"unknown curated model: {args.model}")
        return
    installed = args.model in set(get_installed_models())
    default = _read_default_model() == args.model
    ctx = f"{spec.get('contextWindow', 0) // 1024}k"
    caps = list(spec.get("input", []))
    if spec.get("reasoning"):
        caps.append("reasoning")
    print(bold(args.model))
    print()
    print(spec.get("description", ""))
    print()
    print(f"{'Context':<14} {ctx}")
    print(f"{'Capabilities':<14} {', '.join(caps)}")
    print(f"{'Installed':<14} {'yes' if installed else 'no'}")
    print(f"{'Default':<14} {'yes' if default else 'no'}")


def cmd_status(_args: argparse.Namespace) -> None:
    """Show installed models and current agent configuration."""
    # ── installed ollama models ───────────────────────────────────────────────
    print(bold("Installed ollama models"))
    installed = get_installed_models()
    if installed:
        _table(["Model"], [[green(m)] for m in installed])
    else:
        print(dim("  (none)"))

    # ── agent/settings.json ───────────────────────────────────────────────────
    print()
    print(bold("Agent settings") + dim(f"  ({SETTINGS_PATH})"))
    if not SETTINGS_PATH.exists():
        print(red("  settings.json not found"))
    else:
        cfg = json.loads(SETTINGS_PATH.read_text())
        SHOW_KEYS = ["defaultModel", "defaultProvider", "enableSkillCommands", "quietStartup"]
        rows = []
        for k in SHOW_KEYS:
            if k in cfg:
                rows.append([cyan(k), str(cfg[k])])
        if rows:
            _table(["Key", "Value"], rows)

    # ── agent/models.json ─────────────────────────────────────────────────────
    print()
    print(bold("Configured models") + dim(f"  ({MODELS_PATH})"))
    if not MODELS_PATH.exists():
        print(red("  models.json not found"))
    else:
        data = json.loads(MODELS_PATH.read_text())
        rows = []
        for provider, pdata in data.get("providers", {}).items():
            for m in pdata.get("models", []):
                mid = m.get("id", "?")
                ctx = f"{m['contextWindow'] // 1024}k" if "contextWindow" in m else "?"
                caps = ", ".join(m.get("input", []))
                if m.get("reasoning"):
                    caps += ", reasoning"
                rows.append([green(mid), yellow(provider), cyan(ctx), caps])
        if rows:
            _table(["Model", "Provider", "Context", "Capabilities"], rows)
        else:
            print(dim("  (no models configured)"))
    print()


# ── entry point ───────────────────────────────────────────────────────────────


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="michelle",
        description="Ollama management tool for the pi agent.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
commands:
  move-storage  Move the ollama library to /opt/ollama and symlink back.
                Required when /var/lib is on a small partition.

  load          Make a model the sole resident: pull if missing, set it as
                default, unload every other resident model, and load it
                (default keep_alive: 30m).

  unload        Spin down the default model: ask ollama to evict it from
                memory while leaving it installed on disk.

  models        List the curated set of small-GPU-friendly models.

  status        Print installed models and current agent config files.

examples:
  michelle.py move-storage
  michelle.py load
  michelle.py load qwen2.5-coder:7b
  michelle.py unload
  michelle.py status
""",
    )

    sub = parser.add_subparsers(dest="command", metavar="<command>")

    # move-storage
    p_move = sub.add_parser(
        "move-storage",
        help="move ollama library to /opt/ollama and symlink back",
        description=(
            "Stops the ollama service, moves /var/lib/ollama to /opt/ollama, "
            "creates a symlink so ollama continues to work, then restarts the service."
        ),
    )
    p_move.set_defaults(func=cmd_move_storage)

    # load
    p_load = sub.add_parser(
        "load",
        help="make a model the sole resident in ollama memory",
        description=(
            "Pulls the named model if missing, updates agent/settings.json + "
            "models.json so it becomes the default, unloads every other resident "
            "model, then loads it with the configured keep-alive."
        ),
    )
    p_load.add_argument(
        "model",
        nargs="?",
        default=None,
        metavar="<model>",
        help="model to load (default: defaultModel from agent/settings.json)",
    )
    p_load.add_argument(
        "--keep-alive",
        default="30m",
        metavar="<duration>",
        help="how long ollama should keep the model resident (default: 30m)",
    )
    p_load.set_defaults(func=cmd_load)

    # unload
    p_unload = sub.add_parser(
        "unload",
        help="evict the default model from ollama memory (keeps it installed)",
        description=(
            "Asks ollama to unload the default model from memory by sending an "
            "empty generation request with keep_alive=0. The model stays installed "
            "on disk; the next request will reload it."
        ),
    )
    p_unload.add_argument(
        "--model",
        default=None,
        metavar="<model>",
        help="model to unload (default: defaultModel from agent/settings.json)",
    )
    p_unload.set_defaults(func=cmd_unload)

    # models
    p_models = sub.add_parser(
        "models",
        help="list the curated set of small-GPU-friendly models",
        description="Prints the curated models that fit a 6 GB-VRAM box, marking installed/default.",
    )
    p_models.add_argument(
        "--tsv",
        action="store_true",
        help="emit tab-separated <display>\\t<id> rows (for use as an fzf source)",
    )
    p_models.set_defaults(func=cmd_models)

    # model-info
    p_info = sub.add_parser(
        "model-info",
        help="print a multi-line summary of a single curated model",
        description="Used as the preview source for the turbo-model.sh fzf picker.",
    )
    p_info.add_argument("model", metavar="<model>", help="model id (e.g. 'qwen3:8b')")
    p_info.set_defaults(func=cmd_model_info)

    # status
    p_status = sub.add_parser(
        "status",
        help="show installed models and agent config",
        description="Prints all installed ollama models and the contents of the agent config files.",
    )
    p_status.set_defaults(func=cmd_status)

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(0)
    args.func(args)


if __name__ == "__main__":
    main()
