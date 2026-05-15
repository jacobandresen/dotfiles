#!/usr/bin/env python3
"""michelle — ollama management tool for the pi agent.

Author: Jacob Andresen <jacob.andresen@gmail.com>
"""

import argparse
import getpass
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

# ── constants ────────────────────────────────────────────────────────────────

DEFAULT_MODEL = "gemma4"
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
    cmd = f"echo {password!r} | sudo -S {' '.join(args)}"
    result = subprocess.run(
        ["script", "-q", "-c", cmd, "/dev/null"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        die(f"sudo {' '.join(args)}\n{result.stderr.strip()}")


def validate_password(password: str) -> None:
    cmd = f"echo {password!r} | sudo -S -v"
    result = subprocess.run(
        ["script", "-q", "-c", cmd, "/dev/null"],
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


def pull_model(model: str) -> None:
    print(f"Pulling {model}...")
    result = subprocess.run(["ollama", "pull", model])
    if result.returncode != 0:
        die(f"failed to pull {model}")


def remove_model(model: str) -> None:
    print(f"Removing {model}...")
    result = run(["ollama", "rm", model])
    if result.returncode != 0:
        die(f"failed to remove {model}\n{result.stderr.strip()}")


# ── commands ──────────────────────────────────────────────────────────────────


def cmd_move_storage(_args: argparse.Namespace) -> None:
    """Move ollama library to /opt/ollama and symlink back."""
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


def cmd_enforce(args: argparse.Namespace) -> None:
    """Ensure only the default model is installed and configured."""
    model = args.model

    # ── ollama registry ───────────────────────────────────────────────────────
    installed = get_installed_models()
    print(f"Installed models: {installed or ['(none)']}")

    for m in installed:
        if not m.startswith(model):
            remove_model(m)

    if not any(m.startswith(model) for m in installed):
        pull_model(model)
    else:
        print(f"{model}: already installed ✓")

    # ── agent/settings.json ───────────────────────────────────────────────────
    if not SETTINGS_PATH.exists():
        print(f"WARNING: {SETTINGS_PATH} not found", file=sys.stderr)
    else:
        data = json.loads(SETTINGS_PATH.read_text())
        if data.get("defaultModel") == model:
            print(f"settings.json: defaultModel='{model}' ✓")
        else:
            print(f"settings.json: updating defaultModel -> '{model}'...")
            data["defaultModel"] = model
            SETTINGS_PATH.write_text(json.dumps(data, indent=2) + "\n")
            print("settings.json: updated ✓")

    # ── agent/models.json ─────────────────────────────────────────────────────
    if not MODELS_PATH.exists():
        print(f"WARNING: {MODELS_PATH} not found", file=sys.stderr)
    else:
        data = json.loads(MODELS_PATH.read_text())
        ollama = data.get("providers", {}).get("ollama", {})
        models = ollama.get("models", [])
        kept = [m for m in models if m.get("id", "").startswith(model)]
        removed = [m["id"] for m in models if m not in kept]
        if removed:
            for mid in removed:
                print(f"models.json: removing '{mid}'...")
            ollama["models"] = kept
            MODELS_PATH.write_text(json.dumps(data, indent=2) + "\n")
            print("models.json: updated ✓")
        else:
            print("models.json: no extra models to remove ✓")

    print("\nDone.")


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


# ── system detection ─────────────────────────────────────────────────────────


@dataclass
class SystemInfo:
    cpu_model: str
    physical_cores: int
    logical_threads: int
    ram_mb: int
    gpu_vendor: str          # "nvidia" | "amd" | "intel-arc" | "none"
    gpu_name: str
    governors: list[str] = field(default_factory=list)


def _lscpu_field(output: str, key: str) -> str:
    for line in output.splitlines():
        parts = line.split(":", 1)
        if parts[0].strip() == key:
            return parts[1].strip()
    return ""


def detect_system() -> SystemInfo:
    lscpu = run(["env", "LC_ALL=C", "lscpu"]).stdout

    cpu_model = _lscpu_field(lscpu, "Model name")
    physical_cores = int(_lscpu_field(lscpu, "Core(s) per socket") or 1) * int(
        _lscpu_field(lscpu, "Socket(s)") or 1
    )
    logical_threads = int(_lscpu_field(lscpu, "CPU(s)") or physical_cores)

    ram_mb = 0
    meminfo = Path("/proc/meminfo").read_text()
    m = re.search(r"MemTotal:\s+(\d+)\s+kB", meminfo)
    if m:
        ram_mb = int(m.group(1)) // 1024

    # GPU detection — try NVIDIA first, then AMD, then Intel Arc via lspci
    gpu_vendor, gpu_name = "none", ""
    if run(["which", "nvidia-smi"]).returncode == 0:
        smi = run(["nvidia-smi", "--query-gpu=name", "--format=csv,noheader"])
        if smi.returncode == 0:
            gpu_vendor = "nvidia"
            gpu_name = smi.stdout.strip().splitlines()[0]
    if gpu_vendor == "none":
        lspci = run(["lspci"]).stdout.lower()
        if "amd" in lspci and ("radeon" in lspci or "navi" in lspci or "vega" in lspci):
            gpu_vendor = "amd"
            m2 = re.search(r"vga.*?:\s*(.+)", lspci)
            gpu_name = m2.group(1).strip() if m2 else "AMD GPU"
        elif "intel" in lspci and "arc" in lspci:
            gpu_vendor = "intel-arc"
            gpu_name = "Intel Arc"

    governors: list[str] = []
    gov_path = Path("/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors")
    if gov_path.exists():
        governors = gov_path.read_text().split()

    return SystemInfo(
        cpu_model=cpu_model,
        physical_cores=physical_cores,
        logical_threads=logical_threads,
        ram_mb=ram_mb,
        gpu_vendor=gpu_vendor,
        gpu_name=gpu_name,
        governors=governors,
    )


def compute_ollama_settings(info: SystemInfo) -> dict[str, str]:
    settings: dict[str, str] = {}

    # Threads: physical cores are best for inference; leave one free for the OS
    settings["OLLAMA_NUM_THREADS"] = str(max(1, info.physical_cores - 1))

    # Parallel requests scale with available RAM
    if info.ram_mb < 8 * 1024:
        parallel = 1
    elif info.ram_mb < 16 * 1024:
        parallel = 2
    else:
        parallel = 4
    settings["OLLAMA_NUM_PARALLEL"] = str(parallel)

    # Only load one model at a time unless RAM is generous
    settings["OLLAMA_MAX_LOADED_MODELS"] = "2" if info.ram_mb >= 32 * 1024 else "1"

    # Flash attention is universally beneficial
    settings["OLLAMA_FLASH_ATTENTION"] = "1"

    # Keep model warm for 10 minutes
    settings["OLLAMA_KEEP_ALIVE"] = "10m"

    return settings


OLLAMA_OVERRIDE = Path("/etc/systemd/system/ollama.service.d/override.conf")


def _build_override(settings: dict[str, str]) -> str:
    lines = ["[Service]"]
    for k, v in settings.items():
        lines.append(f'Environment="{k}={v}"')
    return "\n".join(lines) + "\n"


def cmd_optimize(_args: argparse.Namespace) -> None:
    """Detect hardware and write an optimised ollama systemd override."""
    print("Detecting system...")
    info = detect_system()

    print(f"  CPU   : {info.cpu_model}")
    print(f"  Cores : {info.physical_cores} physical / {info.logical_threads} logical")
    print(f"  RAM   : {info.ram_mb} MB ({info.ram_mb // 1024} GB)")
    gpu_label = f"{info.gpu_name} ({info.gpu_vendor})" if info.gpu_vendor != "none" else "none detected"
    print(f"  GPU   : {gpu_label}")
    print(f"  CPU governors: {', '.join(info.governors) or 'unavailable'}")
    print()

    settings = compute_ollama_settings(info)
    print("Computed ollama settings:")
    for k, v in settings.items():
        print(f"  {k}={v}")
    print()

    password = getpass.getpass("sudo password: ")
    validate_password(password)

    # Write systemd override via a temp file then sudo-move into place
    override_content = _build_override(settings)
    sudo(password, "mkdir", "-p", str(OLLAMA_OVERRIDE.parent))

    tmp = Path("/tmp/ollama_override.conf")
    tmp.write_text(override_content)
    sudo(password, "cp", str(tmp), str(OLLAMA_OVERRIDE))
    sudo(password, "chmod", "644", str(OLLAMA_OVERRIDE))
    tmp.unlink(missing_ok=True)
    print(f"Written: {OLLAMA_OVERRIDE} ✓")

    # Set CPU governor to performance if available
    if "performance" in info.governors:
        print("Setting CPU governor to performance...")
        for cpu in Path("/sys/devices/system/cpu").glob("cpu[0-9]*/cpufreq/scaling_governor"):
            sudo(password, "sh", "-c", f"echo performance > {cpu}")
        print("CPU governor: performance ✓")
    else:
        print("CPU governor: performance mode not available, skipping")

    # Reload and restart
    print("Reloading systemd daemon...")
    sudo(password, "systemctl", "daemon-reload")
    print("Restarting ollama...")
    sudo(password, "systemctl", "restart", "ollama")

    print("\nDone.")


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

  enforce       Remove every installed model except the default, pull it
                if missing, and align agent/settings.json + models.json.

  optimize      Detect CPU/RAM/GPU, compute optimal ollama settings, write
                a systemd service override, and restart ollama.

  status        Print installed models and current agent config files.

examples:
  michelle.py move-storage
  michelle.py enforce
  michelle.py enforce --model gemma4:12b
  michelle.py optimize
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

    # enforce
    p_enforce = sub.add_parser(
        "enforce",
        help="ensure only the default model is installed and configured",
        description=(
            "Removes every installed ollama model except the default, pulls it if "
            "missing, and updates agent/settings.json and agent/models.json to match."
        ),
    )
    p_enforce.add_argument(
        "--model",
        default=DEFAULT_MODEL,
        metavar="<model>",
        help=f"model to enforce (default: {DEFAULT_MODEL})",
    )
    p_enforce.set_defaults(func=cmd_enforce)

    # optimize
    p_optimize = sub.add_parser(
        "optimize",
        help="detect hardware and apply optimal ollama settings",
        description=(
            "Reads CPU, RAM, and GPU info from the OS, computes optimal ollama "
            "environment variables, writes a systemd service override, sets the CPU "
            "governor to performance (if available), and restarts ollama."
        ),
    )
    p_optimize.set_defaults(func=cmd_optimize)

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
