#!/usr/bin/env python3
"""Host setup and model commands for this repository."""

import argparse
from contextlib import closing
import getpass
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import sqlite3
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request

import pi_config
from host_tools import HOME, ROOT, api_json, api_ready, coding_model, has_model, ollama_api, ram_profile, run

DOCKER_APP = Path("/Applications/Docker.app")
OLLAMA_APP = Path("/Applications/Ollama.app")
NEOVIM_VERSION = "v0.12.1"
NEOVIM_SHA256 = {"x86_64": "ab757a1fd9ad307d53d2df4045698906a7ca3993d92260dd8fe49108712d57d0",
                 "arm64": "a3f8aa5590fd2ac930bcc5c9070b9ac1ec33461d262b6428874c5fc640f3f13c"}
PI_VERSION = "1.0.4"
PI_SHA256 = {"Linux": {"x86_64": "284c45dd28cf975a13cff6af34741dd0a0cdca6634e8bdfc0083ae7d452e86d6",
                       "arm64": "6a6bc66a6ac2750bd7ccd7f2109090463f564d447feefb10a5965f6b6aed2211"},
             "Darwin": {"x86_64": "665022918678542dd7c87fe7b0da70d2a3dcd926bc6ff4cc712308f2ca313358",
                        "arm64": "717dcd38a03849e919f9dec9daa96f5ca102e15ea33d804e5db57b1d47e513bc"}}
OLLAMA_VERSION = "v0.34.0"
OLLAMA_SHA256 = {"x86_64": "cf95886728959aa09910bb34de5cca1cc5a8f68003b5597197d3f2c2d57c0804",
                 "arm64": "6a9e5b3650c2024d8a78da86b23876f6eea238657a3262d7e5ec0f3688c5d28e"}
LAZYDOCKER_VERSION = "0.24.4"
LAZYDOCKER_SHA256 = {"x86_64": "c47e6f4b61debde5422183c7eb446a704a92c58b4c35bbd128c722d8bf269a86",
                     "arm64": "0fcf85b736895f46daa38eec5871ef1ca3d1e38b20201b2811b26258faccf1c7"}
COMPOSE_VERSION = "v5.6.0"
COMPOSE_SHA256 = {"x86_64": "40343e21ca777173e69cff5dbafeb37c6f81f3b0d57d9e597f036e95eb63e76a",
                  "aarch64": "733ec76717ceb59052a9609b9dadfb523b2df8eab57a54212872d10a58078ea2"}
FONT_VERSION = "v3.5.1"
FONT_SHA256 = "cdd389472e10e2261520140ff1b382b4f8a226af5fd0b2735b975d31151d9c3c"
BREW_COMMIT = "35da6871c4be7d7fdab2fd505fb7fa667926a2a5"
BREW_SHA256 = "5f333bbe53bc490e51e7ccb1df8779b3dd6ee73a1a7379efda216edb08ccb148"
ZSH_COMMIT = "60c9a7a839b790cd905d0fd4419435124fd1bdc0"


def fail(message):
    raise RuntimeError(message)


def download_verified(url, path, sha256):
    try:
        urllib.request.urlretrieve(url, path)
    except OSError as exc:
        fail(f"Download failed: {exc}")
    with path.open("rb") as stream:
        digest = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != sha256:
        path.unlink()
        fail(f"SHA-256 mismatch for {url}")


def release_asset(repo, version, filename, path, sha256):
    download_verified(f"https://github.com/{repo}/releases/download/{version}/{filename}", path, sha256)


def architecture(mapping):
    arch = "arm64" if platform.machine() in ("aarch64", "arm64") else platform.machine()
    if arch not in mapping:
        fail(f"Unsupported architecture: {platform.machine()}")
    return arch


def extract_verified_tar(archive, destination):
    with tarfile.open(archive) as tar:
        if hasattr(tarfile, "data_filter"):
            tar.extractall(destination, filter="data")
        else:
            for member in tar.getmembers():
                if member.name.startswith("/") or ".." in Path(member.name).parts or member.issym() or member.islnk():
                    fail(f"Unsafe archive member: {member.name}")
            tar.extractall(destination)


def link(args):
    source, target = Path(args.source).resolve(), Path(args.target)
    if not source.exists():
        fail(f"Missing source: {source}")
    if target.is_symlink():
        if target.resolve() != source:
            fail(f"{target} points elsewhere")
        print(f"  ✓ {target} already symlinked")
        return
    if target.exists():
        if args.policy == "skip":
            print(f"  ⚠ {target} exists and is not a symlink — skipping")
            return
        backup = target.with_name(target.name + ".bak")
        if backup.exists() or backup.is_symlink():
            fail(f"Backup already exists: {backup}")
        target.rename(backup)
        print(f"  ✓ backed up {target} -> {backup}")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.symlink_to(source)
    print(f"  ✓ {target} -> {source}")


def compatible_nvim(path):
    result = run(path, "--version", check=False, capture_output=True, text=True)
    match = re.search(r"NVIM v(\d+)\.(\d+)", result.stdout)
    return result.returncode == 0 and match is not None and tuple(map(int, match.groups())) >= (0, 12)


def install_neovim(_):
    current = shutil.which("nvim")
    if current and compatible_nvim(current):
        print("Neovim >= 0.12 is already installed")
        return
    arch = architecture(NEOVIM_SHA256)
    archive = f"nvim-linux-{arch}"
    with tempfile.TemporaryDirectory() as work:
        tar_path = Path(work) / "nvim.tar.gz"
        release_asset("neovim/neovim", NEOVIM_VERSION, archive + ".tar.gz", tar_path, NEOVIM_SHA256[arch])
        extract_verified_tar(tar_path, work)
        binary = Path(work) / archive / "bin/nvim"
        if not compatible_nvim(str(binary)):
            fail("Pinned Neovim release is older than 0.12")
        first = run(str(binary), "--version", capture_output=True, text=True).stdout.splitlines()[0]
        destination = HOME / ".local/share/neovim" / (first.replace(" ", "_").replace("/", "_") + f"-{arch}")
        target = HOME / ".local/bin/nvim"
        if target.exists() and not target.is_symlink():
            fail("Refusing to overwrite an existing ~/.local/bin/nvim executable")
        destination.parent.mkdir(parents=True, exist_ok=True)
        if not destination.exists():
            shutil.copytree(Path(work) / archive, destination)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.unlink(missing_ok=True)
        target.symlink_to(destination / "bin/nvim")
        print(f"Installed Neovim in {destination}")


def docker_macos(_):
    profile = ram_profile()
    source = ROOT / "docker/desktop" / f"{profile}.json"
    if not source.is_file():
        fail(f"No macOS Docker profile at {source}")
    if not DOCKER_APP.is_dir():
        print("  Docker Desktop not found — skipping (make deps-docker-macos)")
        return
    group = HOME / "Library/Group Containers/group.com.docker"
    settings = next((path for path in (group / "settings-store.json", group / "settings.json") if path.is_file()), group / "settings-store.json")
    if not settings.exists():
        group.mkdir(parents=True, exist_ok=True)
        settings.write_text("{}\n")
        print(f"  created {settings} (first run)")
    current, desired = json.loads(settings.read_text()), json.loads(source.read_text())
    changes = {key: value for key, value in desired.items() if not key.startswith("_") and current.get(key) != value}
    print(f"  RAM profile: {profile} (from {source})")
    if not changes:
        print(f"  Docker Desktop settings already match the {profile} profile")
        return
    running = run("pgrep", "-x", "Docker", check=False, stdout=subprocess.DEVNULL).returncode == 0 or run("pgrep", "-f", "Docker Desktop", check=False, stdout=subprocess.DEVNULL).returncode == 0
    if running:
        print("  quitting Docker Desktop before rewriting its settings...")
        run("osascript", "-e", 'quit app "Docker"', check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(30):
            if run("pgrep", "-f", "Docker Desktop", check=False, stdout=subprocess.DEVNULL).returncode != 0:
                break
            time.sleep(1)
        else:
            fail("Docker Desktop did not quit; settings were not changed")
    shutil.copy2(settings, settings.with_name(settings.name + ".bak"))
    for key, value in changes.items():
        print(f"     {key}: {current.get(key)!r} -> {value!r}")
    current.update(changes)
    settings.write_text(json.dumps(current, indent=2) + "\n")
    print(f"  {settings} updated (backup at {settings}.bak)")
    if running:
        run("open", "-a", "Docker")
        print(f"  Docker Desktop restarted with the {profile} profile")
    else:
        print("  settings applied — they take effect next time Docker Desktop starts")


def ollama_macos(_):
    profile = ram_profile()
    source = ROOT / "ollama/launchd" / f"{profile}.env"
    if not source.is_file():
        fail(f"No macOS Ollama profile at {source}")
    print(f"  RAM profile: {profile} (from {source})")
    app = OLLAMA_APP
    if not shutil.which("ollama") and not app.is_dir():
        print("  Ollama not found — skipping (brew install --cask ollama)")
        return
    values = dict(line.split("=", 1) for line in source.read_text().splitlines() if line and not line.startswith("#"))
    database = HOME / "Library/Application Support/Ollama/db.sqlite"
    context = values.get("OLLAMA_CONTEXT_LENGTH")
    current_context = None
    if context and database.is_file():
        with closing(sqlite3.connect(database)) as db:
            row = db.execute("select context_length from settings limit 1").fetchone()
            current_context = str(row[0]) if row else None
    needs_update = current_context is not None and current_context != context
    running = run("pgrep", "-x", "Ollama", check=False, stdout=subprocess.DEVNULL).returncode == 0
    if running and needs_update:
        print("  quitting Ollama.app before reconfiguring...")
        if run("osascript", "-e", 'quit app "Ollama"', check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
            run("pkill", "-x", "Ollama", check=False)
        time.sleep(3)
    for key, value in values.items():
        run("launchctl", "setenv", key, value)
        print(f"     {key}={value}")
    env_path = HOME / ".ollama/dotfiles.env"
    env_path.parent.mkdir(parents=True, exist_ok=True)
    env_text = f"# Generated by scripts/dotfiles.py — do not edit.\n# Source profile: ollama/launchd/{profile}.env\n" + "".join(f"export {key}={value}\n" for key, value in values.items())
    if not env_path.exists() or env_path.read_text() != env_text:
        env_path.write_text(env_text)
        print("  wrote ~/.ollama/dotfiles.env (sourced by ~/.zshrc)")
    if context and database.is_file():
        if current_context is None:
            print("  Ollama.app has no settings row yet (finish its first-run setup, then re-run)", file=sys.stderr)
        elif needs_update:
            with closing(sqlite3.connect(database)) as db, db:
                with closing(sqlite3.connect(str(database) + ".bak")) as backup:
                    db.backup(backup)
                db.execute("update settings set context_length=?", (int(context),))
            print(f"  Ollama.app context length {current_context} -> {context} (backup at db.sqlite.bak)")
        else:
            print(f"  Ollama.app context length already {context}")
    elif context:
        print("  Ollama.app settings store not found; context length applies only to a shell-started 'ollama serve'")
    if app.is_dir():
        if not running or needs_update:
            run("open", "-a", "Ollama")
            print(f"  Ollama.app running with the {profile} profile")
        else:
            print(f"  Ollama.app already running with the {profile} profile")
    elif running:
        print("  Ollama.app was running but is not installed at /Applications — not restarted", file=sys.stderr)
    else:
        print("  Ollama.app not installed — env applied for CLI 'ollama serve' only")


def install_homebrew(_):
    if shutil.which("brew"):
        return
    with tempfile.TemporaryDirectory() as work:
        script = Path(work) / "install.sh"
        download_verified(f"https://raw.githubusercontent.com/Homebrew/install/{BREW_COMMIT}/install.sh", script, BREW_SHA256)
        run("/bin/bash", str(script))


def install_pi_binary():
    system = platform.system()
    if system not in PI_SHA256:
        fail(f"Unsupported Pi platform: {system}")
    arch = architecture(PI_SHA256[system])
    filename = f"pi-{'linux' if system == 'Linux' else 'darwin'}-{'x64' if arch == 'x86_64' else 'arm64'}.tar.gz"
    destination = HOME / ".local/share/pi" / PI_VERSION
    target = HOME / ".local/bin/pi"
    with tempfile.TemporaryDirectory() as work:
        archive = Path(work) / filename
        release_asset("earendil-works/pi", f"v{PI_VERSION}", filename, archive, PI_SHA256[system][arch])
        extract_verified_tar(archive, work)
        destination.parent.mkdir(parents=True, exist_ok=True)
        if not destination.exists():
            shutil.move(str(Path(work) / "pi"), destination)
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() and not target.is_symlink():
        fail(f"Refusing to overwrite {target}")
    target.unlink(missing_ok=True)
    target.symlink_to(destination / "pi")
    run(str(target), "--version")


def install_ollama_binary():
    arch = architecture(OLLAMA_SHA256)
    name = f"ollama-linux-{'amd64' if arch == 'x86_64' else 'arm64'}.tar.zst"
    with tempfile.TemporaryDirectory() as work:
        archive = Path(work) / name
        release_asset("ollama/ollama", OLLAMA_VERSION, name, archive, OLLAMA_SHA256[arch])
        run("sudo", "tar", "--zstd", "-xf", str(archive), "-C", "/usr/local")
    if run("id", "ollama", check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
        run("sudo", "useradd", "--system", "--user-group", "--create-home", "--home-dir", "/usr/share/ollama", "--shell", "/usr/sbin/nologin", "ollama")
    for group in ("render", "video"):
        if run("getent", "group", group, check=False, stdout=subprocess.DEVNULL).returncode == 0:
            run("sudo", "usermod", "-aG", group, "ollama")
    service = "[Unit]\nDescription=Ollama Service\nAfter=network-online.target\n\n[Service]\nExecStart=/usr/local/bin/ollama serve\nUser=ollama\nGroup=ollama\nRestart=always\nRestartSec=3\n\n[Install]\nWantedBy=multi-user.target\n"
    run("sudo", "tee", "/etc/systemd/system/ollama.service", input=service.encode(), stdout=subprocess.DEVNULL)
    run("sudo", "systemctl", "daemon-reload")
    run("sudo", "systemctl", "enable", "--now", "ollama")


def install_lazydocker_binary():
    arch = architecture(LAZYDOCKER_SHA256)
    name = f"lazydocker_{LAZYDOCKER_VERSION}_Linux_{arch}.tar.gz"
    target = HOME / ".local/bin/lazydocker"
    with tempfile.TemporaryDirectory() as work:
        archive = Path(work) / name
        release_asset("jesseduffield/lazydocker", f"v{LAZYDOCKER_VERSION}", name, archive, LAZYDOCKER_SHA256[arch])
        with tarfile.open(archive) as tar:
            binary = tar.extractfile("lazydocker")
            if binary is None:
                fail("Lazydocker archive has no binary")
            target.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as output:
                staged = Path(output.name)
                shutil.copyfileobj(binary, output)
            try:
                staged.chmod(0o755)
                staged.replace(target)
            finally:
                staged.unlink(missing_ok=True)


def cli_tools(_):
    zsh = Path(os.environ.get("ZSH", HOME / ".oh-my-zsh"))
    if not (zsh / "oh-my-zsh.sh").is_file():
        zsh.parent.mkdir(parents=True, exist_ok=True)
        run("git", "clone", "--no-checkout", "https://github.com/ohmyzsh/ohmyzsh.git", str(zsh))
        run("git", "-C", str(zsh), "checkout", "--detach", ZSH_COMMIT)
    if not shutil.which("fd") and shutil.which("fdfind"):
        target = HOME / ".local/bin/fd"
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists() and not target.is_symlink():
            target.symlink_to(shutil.which("fdfind"))
    if not shutil.which("pi"):
        install_pi_binary()
    if not shutil.which("ollama"):
        if platform.system() == "Darwin":
            fail("Install Ollama with: brew install --cask ollama")
        install_ollama_binary()
    if not shutil.which("lazydocker"):
        if platform.system() == "Darwin":
            run("brew", "install", "lazydocker")
        else:
            install_lazydocker_binary()


def install_compose(_):
    if run("docker", "compose", "version", check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
        print("  ✓ docker compose already installed")
        return
    target = HOME / ".docker/cli-plugins/docker-compose"
    target.parent.mkdir(parents=True, exist_ok=True)
    arch = architecture(COMPOSE_SHA256)
    with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as handle:
        temporary = Path(handle.name)
    try:
        release_asset("docker/compose", COMPOSE_VERSION, f"docker-compose-linux-{arch}", temporary, COMPOSE_SHA256[arch])
        temporary.chmod(0o755)
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)
    run("docker", "compose", "version")


def install_fonts(_):
    if shutil.which("fc-list") and "hack nerd font" in run("fc-list", check=False, capture_output=True, text=True).stdout.casefold():
        print("  ✓ Hack Nerd Font already installed")
        return
    if platform.system() == "Darwin":
        run("brew", "install", "--cask", "font-hack-nerd-font")
        return
    destination = HOME / ".local/share/fonts/HackNerdFont"
    with tempfile.TemporaryDirectory() as work:
        archive = Path(work) / "Hack.tar.xz"
        release_asset("ryanoasis/nerd-fonts", FONT_VERSION, "Hack.tar.xz", archive, FONT_SHA256)
        destination.mkdir(parents=True, exist_ok=True)
        run("tar", "-xJf", str(archive), "-C", str(destination))
    run("fc-cache", "-f", str(destination.parent), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f"  ✓ Hack Nerd Font -> {destination}")


def install_ollama(_):
    if platform.system() == "Darwin":
        ollama_macos(None)
        return
    if platform.system() != "Linux":
        print(f"  ⚠ skipping Ollama tuning (unsupported OS: {platform.system()})")
        return
    profile = ram_profile()
    override = ROOT / "ollama/ollama.service.d" / f"override-{profile}.conf"
    service = (ROOT / "ollama/ollama-warm-model.service").read_text()
    service = service.replace("__USER__", getpass.getuser()).replace("__REPO_DIR__", str(ROOT))
    run("sudo", "mkdir", "-p", "/etc/systemd/system/ollama.service.d")
    run("sudo", "cp", str(override), "/etc/systemd/system/ollama.service.d/override.conf")
    run("sudo", "tee", "/etc/systemd/system/ollama-warm-model.service", input=service.encode(), stdout=subprocess.DEVNULL)
    run("sudo", "systemctl", "daemon-reload")
    run("sudo", "systemctl", "restart", "ollama")
    print(f"  ✓ Ollama {profile} profile and warm-model service installed")


def install_docker(_):
    if platform.system() == "Darwin":
        docker_macos(None)
        return
    if platform.system() != "Linux":
        print(f"  ⚠ skipping Docker tuning (unsupported OS: {platform.system()})")
        return
    if not shutil.which("docker") and run("systemctl", "list-unit-files", "docker.service", check=False,
                                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
        print("  ⚠ Docker not found — skipping (install it first)")
        return
    profile = ram_profile()
    override = ROOT / "docker/docker.service.d" / f"override-{profile}.conf"
    run("sudo", "mkdir", "-p", "/etc/systemd/system/docker.service.d")
    run("sudo", "cp", str(override), "/etc/systemd/system/docker.service.d/override.conf")
    run("sudo", "systemctl", "daemon-reload")
    run("sudo", "systemctl", "restart", "docker")
    print(f"  ✓ Docker {profile} profile installed")


def show_profile(_):
    profile = ram_profile()
    print(f"RAM profile:   {profile}\nCoding model:  {coding_model()}")
    if platform.system() == "Darwin":
        print(f"Ollama config: ollama/launchd/{profile}.env\nDocker config: docker/desktop/{profile}.json")
    else:
        print(f"Ollama config: ollama/ollama.service.d/override-{profile}.conf\nDocker config: docker/docker.service.d/override-{profile}.conf")


def doctor(_):
    commands = ("git", "curl", "python3", "zsh", "rg", "fd", "jq", "make", "cc", "pkg-config",
                "node", "npm", "unzip", "tar", "base64", "kitty", "mc", "pi", "ollama", "lazydocker")
    missing = False
    for command in commands:
        found = shutil.which(command) is not None
        print(f"{'OK' if found else 'MISSING'} {command}")
        missing |= not found
    nvim = shutil.which("nvim")
    valid_nvim = bool(nvim and compatible_nvim(nvim))
    print(f"{'OK' if valid_nvim else 'MISSING/OLD'} Neovim >= 0.12")
    missing |= not valid_nvim
    zsh = Path(os.environ.get("ZSH", HOME / ".oh-my-zsh")) / "oh-my-zsh.sh"
    print(f"{'OK' if zsh.is_file() else 'MISSING'} Oh My Zsh")
    missing |= not zsh.is_file()
    docker = shutil.which("docker")
    compose = bool(docker and run(docker, "compose", "version", check=False, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL).returncode == 0)
    optional = platform.system() == "Darwin"
    print(f"{'OK' if compose else 'OPTIONAL' if optional else 'MISSING'} Docker + Compose")
    if missing or (not optional and not compose):
        fail("Missing tools; run make deps")


def start_ollama():
    if platform.system() == "Darwin":
        try:
            if run("open", "-a", "Ollama", check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
                return
        except OSError:
            pass
    subprocess.Popen([shutil.which("ollama") or "ollama", "serve"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


def install_pi(model, dry_run=False):
    command = ["--agent-dir", os.environ.get("PI_CODING_AGENT_DIR", str(HOME / ".pi/agent")),
               "--model", model, "--api", ollama_api()]
    if dry_run:
        command.append("--dry-run")
    pi_config.main(command)


def setup_host(args):
    if not shutil.which("ollama"):
        fail("Ollama not found. Install it first.")
    if not api_ready("/v1/models"):
        print("  Ollama server is not running. Starting it...")
        if args.dry_run:
            print("  [DRY-RUN] Would start Ollama server")
        else:
            start_ollama()
            time.sleep(5)
            if not api_ready("/v1/models"):
                fail("Failed to start Ollama server. Start it manually, then re-run.")
            print("  Ollama server started")
    selected = coding_model()
    try:
        loaded = api_json("/api/ps", timeout=2).get("models", [])
        loaded_name = loaded[0]["name"] if loaded else None
    except (OSError, ValueError, KeyError):
        loaded_name = None
    if args.use_loaded:
        if not loaded_name:
            fail("--use-loaded given, but Ollama has no model resident. Load one first: ollama run <model>")
        model = loaded_name
        print(f"  using the resident model: {model} (--use-loaded)")
        if model != selected:
            print(f"  this host's selector picks {selected}, not {model}.")
            print(f"    Check it with: python3 scripts/dotfiles.py verify-model {model}")
    else:
        model = selected
        print(f"  this host's model: {model}")
        if loaded_name and loaded_name != model:
            print(f"  Ollama currently has {loaded_name} resident — ignoring it.")
    install_pi(model, args.dry_run)


def use_model(args):
    model = args.model or coding_model()
    keepalive = args.keepalive or os.environ.get("KEEPALIVE", "4h")
    print(f"{'Setting up Ollama model' if args.ollama_only else 'Pointing the local stack at'}: {model}")
    if not shutil.which("ollama"):
        if args.skip_if_unavailable:
            print("  Ollama not found — skipping model setup (run 'make deps' first).")
            return
        fail("Ollama not found — install it first.")
    if args.dry_run:
        if not api_ready():
            print(f"  [DRY-RUN] Would start Ollama at {ollama_api()}")
            print(f"  [DRY-RUN] Would ensure {model} is pulled and loaded (keep-alive {keepalive})")
        else:
            print(f"  {model} is present" if has_model(model) else f"  [DRY-RUN] Would pull {model}")
            print(f"  [DRY-RUN] Would load {model} (keep-alive {keepalive})")
        if not args.ollama_only:
            print(f"  [DRY-RUN] Would configure Pi to use {model}")
        return
    if not api_ready():
        print(f"  Ollama not responding at {ollama_api()} — starting it...")
        start_ollama()
        for _ in range(10):
            if api_ready():
                break
            time.sleep(1)
    if not api_ready():
        if args.skip_if_unavailable:
            print(f"  Ollama is not responding at {ollama_api()} — skipping model setup.", file=sys.stderr)
            return
        fail(f"Ollama unreachable at {ollama_api()}")
    print(f"  Ollama responding at {ollama_api()}")
    if has_model(model):
        print(f"  {model} is present")
    else:
        print(f"  pulling {model}...")
        run("ollama", "pull", model)
    print(f"  loading {model} (keep-alive {keepalive})...")
    response = api_json("/api/generate", {"model": model, "prompt": "hi", "stream": False, "think": False, "keep_alive": keepalive}, timeout=900)
    if response.get("error"):
        fail(response["error"])
    print(f"  {model} loaded")
    if not args.ollama_only:
        install_pi(model)


def verify_model(args):
    models = args.models or [coding_model()]
    prompt = "Create hello.c in the current directory: a C program that prints Hello, World! Then compile it with `cc hello.c -o hello` and run ./hello. Use your tools to do this; do not just show me the code."
    print(f"\n{'MODEL':22} {'WROTE':8} {'COMPILES':10} {'RUNS':9} VERDICT")
    print("-" * 70)
    failed = False
    for model in models:
        if not has_model(model):
            print(f"  pulling {model}...", file=sys.stderr)
            if run("ollama", "pull", model, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
                print(f"{model:22} {'-':8} {'-':10} {'-':9} PULL FAILED")
                failed = True
                continue
        work = Path(tempfile.mkdtemp())
        with (work / "pi.log").open("w") as log:
            run("pi", "-p", "--provider", "ollama", "--model", model, "--no-session", "-nc", prompt,
                cwd=work, stdout=log, stderr=subprocess.STDOUT, check=False)
        source = next((p for p in sorted(work.glob("*.c")) if p.stat().st_size), None)
        wrote = source is not None
        compiles = runs = False
        if source:
            with (work / "cc.log").open("w") as log:
                compiles = run(os.environ.get("CC", "cc"), "-std=c11", "-Wall", str(source), "-o", str(work / "verify.bin"),
                               stdout=log, stderr=subprocess.STDOUT, check=False).returncode == 0
            if compiles:
                result = run(str(work / "verify.bin"), check=False, capture_output=True, text=True)
                runs = result.returncode == 0 and "hello" in result.stdout.lower()
        verdict = "PASS" if runs else "FAIL"
        print(f"{model:22} {('yes' if wrote else 'no'):8} {('yes' if compiles else 'no'):10} {('yes' if runs else 'no'):9} {verdict}")
        if runs:
            shutil.rmtree(work)
        else:
            failed = True
            print(f"    artifacts: {work}", file=sys.stderr)
    if failed:
        fail("Model verification failed")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name, func in (("install-homebrew", install_homebrew), ("install-neovim", install_neovim), ("install-cli-tools", cli_tools),
                       ("install-compose", install_compose),
                       ("install-fonts", install_fonts), ("install-ollama", install_ollama),
                       ("install-docker", install_docker), ("show-profile", show_profile),
                       ("doctor", doctor)):
        commands.add_parser(name).set_defaults(func=func)
    p = commands.add_parser("install-link")
    p.add_argument("policy", choices=("skip", "backup"))
    p.add_argument("source")
    p.add_argument("target")
    p.set_defaults(func=link)
    p = commands.add_parser("setup-host")
    p.add_argument("-n", "--dry-run", action="store_true")
    p.add_argument("--use-loaded", action="store_true")
    p.set_defaults(func=setup_host)
    p = commands.add_parser("use-model")
    p.add_argument("model", nargs="?")
    p.add_argument("-n", "--dry-run", action="store_true")
    p.add_argument("--keepalive")
    p.add_argument("--ollama-only", action="store_true")
    p.add_argument("--skip-if-unavailable", action="store_true")
    p.set_defaults(func=use_model)
    p = commands.add_parser("verify-model")
    p.add_argument("models", nargs="*")
    p.set_defaults(func=verify_model)
    args = parser.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, sqlite3.Error, subprocess.CalledProcessError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)
