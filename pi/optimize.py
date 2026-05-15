#!/usr/bin/env python3
"""optimize — tune ollama for high throughput on the host hardware.

Assumes the working model is already pulled and resident (cache primed), so
we optimize for aggregate tokens/sec across concurrent requests rather than
single-request latency or multi-model flexibility. See
compute_ollama_settings() for the specific choices.

Author: Jacob Andresen <jacob.andresen@gmail.com>
"""

import argparse
import getpass
import platform
import plistlib
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

IS_MACOS = platform.system() == "Darwin"
OLLAMA_LAUNCHD_PLIST = Path.home() / "Library" / "LaunchAgents" / "homebrew.mxcl.ollama.plist"
OLLAMA_OVERRIDE = Path("/etc/systemd/system/ollama.service.d/override.conf")


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True)


def die(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


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


# ── system detection ─────────────────────────────────────────────────────────


@dataclass
class SystemInfo:
    cpu_model: str
    physical_cores: int
    logical_threads: int
    ram_mb: int
    gpu_vendor: str          # "nvidia" | "amd" | "intel-arc" | "apple" | "none"
    gpu_name: str
    governors: list[str] = field(default_factory=list)


def _lscpu_field(output: str, key: str) -> str:
    for line in output.splitlines():
        parts = line.split(":", 1)
        if parts[0].strip() == key:
            return parts[1].strip()
    return ""


def _sysctl(key: str) -> str:
    return run(["sysctl", "-n", key]).stdout.strip()


def detect_system() -> SystemInfo:
    if IS_MACOS:
        cpu_model = _sysctl("machdep.cpu.brand_string") or f"Apple {platform.machine()}"
        physical_cores = int(_sysctl("hw.physicalcpu") or 1)
        logical_threads = int(_sysctl("hw.logicalcpu") or physical_cores)
        ram_mb = int(_sysctl("hw.memsize") or 0) // (1024 * 1024)

        if platform.machine() == "arm64":
            gpu_vendor, gpu_name = "apple", "Apple Silicon (Metal)"
        else:
            gpu_vendor, gpu_name = "none", ""
            sp = run(["system_profiler", "SPDisplaysDataType"]).stdout.lower()
            if "amd" in sp or "radeon" in sp:
                gpu_vendor = "amd"
                m2 = re.search(r"chipset model:\s*(.+)", sp)
                gpu_name = m2.group(1).strip() if m2 else "AMD GPU"
            elif "nvidia" in sp:
                gpu_vendor = "nvidia"
                m2 = re.search(r"chipset model:\s*(.+)", sp)
                gpu_name = m2.group(1).strip() if m2 else "NVIDIA GPU"

        return SystemInfo(
            cpu_model=cpu_model,
            physical_cores=physical_cores,
            logical_threads=logical_threads,
            ram_mb=ram_mb,
            gpu_vendor=gpu_vendor,
            gpu_name=gpu_name,
            governors=[],
        )

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
    """Tune ollama for throughput, assuming the model is already cached.

    Priorities, in order: aggregate tokens/sec under concurrent load, single
    resident model (no eviction churn), KV cache budget that scales with
    parallel slots. Per-request latency takes a back seat to total throughput.
    """
    settings: dict[str, str] = {}

    # Threads: use all physical cores. Inference is memory-bandwidth bound;
    # leaving cores idle leaves throughput on the table when slots batch.
    settings["OLLAMA_NUM_THREADS"] = str(max(1, info.physical_cores))

    # Multiple parallel slots = continuous batching = higher aggregate
    # throughput. 2 keeps KV cache + CPU contention manageable on small boxes.
    settings["OLLAMA_NUM_PARALLEL"] = "2"

    # Deep queue so bursts don't get rejected under load
    settings["OLLAMA_MAX_QUEUE"] = "512"

    # Pin a single resident model so a sibling pull/load never evicts the
    # primed model from VRAM
    settings["OLLAMA_MAX_LOADED_MODELS"] = "1"

    # Spread layers across all available GPUs when present
    settings["OLLAMA_SCHED_SPREAD"] = "1"

    # Flash attention is universally beneficial
    settings["OLLAMA_FLASH_ATTENTION"] = "1"

    # q8_0 KV cache: half the VRAM of f16 with negligible quality loss —
    # critical when NUM_PARALLEL multiplies the cache footprint
    settings["OLLAMA_KV_CACHE_TYPE"] = "q8_0"

    # 8k per-slot context: effective budget is 8k * NUM_PARALLEL = 32k of KV
    # cache. Larger per-slot windows blow up VRAM and tank batch throughput.
    settings["OLLAMA_CONTEXT_LENGTH"] = "8192"

    # Keep the model resident indefinitely (cache is primed)
    settings["OLLAMA_KEEP_ALIVE"] = "-1"

    return settings


def _build_override(settings: dict[str, str]) -> str:
    lines = ["[Service]"]
    for k, v in settings.items():
        lines.append(f'Environment="{k}={v}"')
    return "\n".join(lines) + "\n"


def _write_launchd_env(settings: dict[str, str]) -> None:
    """Update EnvironmentVariables in the homebrew ollama launchd plist."""
    if not OLLAMA_LAUNCHD_PLIST.exists():
        die(
            f"launchd plist not found: {OLLAMA_LAUNCHD_PLIST}\n"
            "Start ollama as a brew service first: brew services start ollama"
        )
    with open(OLLAMA_LAUNCHD_PLIST, "rb") as f:
        plist = plistlib.load(f)
    plist.setdefault("EnvironmentVariables", {}).update(settings)
    with open(OLLAMA_LAUNCHD_PLIST, "wb") as f:
        plistlib.dump(plist, f)
    print(f"Written: {OLLAMA_LAUNCHD_PLIST} ✓")
    print("Note: re-run 'turbo-optimize.sh' after 'brew services stop/start ollama'.")


def main() -> None:
    argparse.ArgumentParser(
        prog="turbo-optimize",
        description=(
            "Tune ollama for throughput. Detects CPU/RAM/GPU, computes "
            "high-throughput ollama settings (2 parallel slots, 8k per-slot "
            "context, q8_0 KV cache, deep queue, single resident model, "
            "keep-alive forever), writes a systemd service override (Linux) or "
            "launchd plist env (macOS), pins the CPU governor to performance "
            "when available, and restarts ollama. Assumes the model you intend "
            "to use is already pulled."
        ),
    ).parse_args()

    print("Detecting system...")
    info = detect_system()

    print(f"  CPU   : {info.cpu_model}")
    print(f"  Cores : {info.physical_cores} physical / {info.logical_threads} logical")
    print(f"  RAM   : {info.ram_mb} MB ({info.ram_mb // 1024} GB)")
    gpu_label = f"{info.gpu_name} ({info.gpu_vendor})" if info.gpu_vendor != "none" else "none detected"
    print(f"  GPU   : {gpu_label}")
    if not IS_MACOS:
        print(f"  CPU governors: {', '.join(info.governors) or 'unavailable'}")
    print()

    settings = compute_ollama_settings(info)
    print("Computed ollama settings:")
    for k, v in settings.items():
        print(f"  {k}={v}")
    print()

    if IS_MACOS:
        _write_launchd_env(settings)
        print("Restarting ollama...")
        result = subprocess.run(["brew", "services", "restart", "ollama"], capture_output=True, text=True)
        if result.returncode != 0:
            die(f"failed to restart ollama: {result.stderr.strip()}")
        print("ollama restarted ✓")
    else:
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


if __name__ == "__main__":
    main()
