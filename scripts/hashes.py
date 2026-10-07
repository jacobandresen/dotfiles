#!/usr/bin/env python3
"""Load and update pinned dependency hashes."""

import json
from pathlib import Path
import platform
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

HASHES_FILE = Path(__file__).with_name("hashes.json")
DEPENDENCY_HASHES = json.loads(HASHES_FILE.read_text())


def log(message):
    print(f"[deps] {message}")


def fetch(url, timeout=30):
    request = urllib.request.Request(url, headers={"User-Agent": "dotfiles-dependency-updater"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def latest(repo):
    log(f"checking latest release: {repo}")
    return json.loads(fetch(f"https://api.github.com/repos/{repo}/releases/latest"))["tag_name"]


def sha256(path):
    import hashlib

    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def hash_asset(repo, tag, name, temporary):
    log(f"fetching hash for {repo}/{tag}/{name}")
    release = json.loads(fetch(f"https://api.github.com/repos/{repo}/releases/tags/{tag}"))
    for asset in release.get("assets", []):
        if asset["name"] == name and asset.get("digest", "").startswith("sha256:"):
            digest = asset["digest"][len("sha256:") :]
            if re.fullmatch(r"[0-9a-f]{64}", digest):
                log(f"using upstream digest for {name}: {digest}")
                return digest

    log(f"no upstream digest; downloading and hashing {name}")
    path = temporary / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(fetch(f"https://github.com/{repo}/releases/download/{tag}/{name}", timeout=180))
    digest = sha256(path)
    log(f"verified {name} ({path.stat().st_size} bytes): {digest}")
    return digest


def replace_constant(text, key, value):
    updated, count = re.subn(
        rf"^{re.escape(key)}\s*=\s*[^\n]+",
        f"{key} = {value}",
        text,
        count=1,
        flags=re.MULTILINE,
    )
    if count != 1:
        raise RuntimeError(f"could not update {key}")
    return updated


def validate(text, hashes):
    keys = (
        "PI_VERSION", "PI_SHA256", "OLLAMA_VERSION",
        "OLLAMA_SHA256", "COMPOSE_VERSION", "COMPOSE_SHA256",
    )
    missing = [key for key in keys if not re.search(rf"^{key}\s*=", text, re.MULTILINE)]
    if missing:
        raise RuntimeError(f"updated file is missing install constants: {' '.join(missing)}")
    required = ("neovim", "pi", "ollama", "lazydocker", "compose", "font", "homebrew")
    if any(key not in hashes for key in required):
        raise RuntimeError("dependency hash file is missing required entries")
    if any(not re.fullmatch(r"[0-9a-f]{64}", digest)
           for value in hashes.values()
           for digest in (value.values() if isinstance(value, dict) else [value])
           if not isinstance(digest, dict)):
        raise RuntimeError("dependency hash file contains an invalid SHA-256 digest")



def main():
    system = platform.system()
    if system == "Darwin":
        host_platform = "macOS"
    elif system == "Linux":
        host_platform = "Linux (Arch/Debian/Ubuntu)"
    else:
        raise RuntimeError(f"unsupported platform: {system}; Makefile supports macOS, Arch, Debian, and Ubuntu")
    log(f"host platform: {host_platform}")

    file = Path(sys.argv[1] if len(sys.argv) > 1 else "scripts/dotfiles.py")
    hashes_file = HASHES_FILE
    log(f"updating {file}")
    report = []
    with tempfile.TemporaryDirectory() as directory:
        temporary = Path(directory)

        pi_tag = latest("earendil-works/pi")
        pi_hashes = [
            hash_asset("earendil-works/pi", pi_tag, name, temporary)
            for name in ("pi-linux-x64.tar.gz", "pi-linux-arm64.tar.gz",
                         "pi-darwin-x64.tar.gz", "pi-darwin-arm64.tar.gz")
        ]
        text = file.read_text()
        hashes = json.loads(hashes_file.read_text())
        text = replace_constant(text, "PI_VERSION", repr(pi_tag.removeprefix("v")))
        hashes["pi"] = {"Linux": {"x86_64": pi_hashes[0], "arm64": pi_hashes[1]},
                        "Darwin": {"x86_64": pi_hashes[2], "arm64": pi_hashes[3]}}
        report.append(f"pi={pi_tag} hashes={','.join(pi_hashes)}")

        ollama_tag = latest("ollama/ollama")
        ollama_hashes = [
            hash_asset("ollama/ollama", ollama_tag, name, temporary)
            for name in ("ollama-linux-amd64.tar.zst", "ollama-linux-arm64.tar.zst")
        ]
        text = replace_constant(text, "OLLAMA_VERSION", repr(ollama_tag))
        hashes["ollama"] = {"x86_64": ollama_hashes[0], "arm64": ollama_hashes[1]}
        report.append(f"ollama={ollama_tag} hashes={','.join(ollama_hashes)}")

        compose_tag = latest("docker/compose")
        compose_hashes = [
            hash_asset("docker/compose", compose_tag, name, temporary)
            for name in ("docker-compose-linux-x86_64", "docker-compose-linux-aarch64")
        ]
        text = replace_constant(text, "COMPOSE_VERSION", repr(compose_tag))
        hashes["compose"] = {"x86_64": compose_hashes[0], "aarch64": compose_hashes[1]}
        report.append(f"compose={compose_tag} hashes={','.join(compose_hashes)}")

        validate(text, hashes)
        file.write_text(text)
        hashes_file.write_text(json.dumps(hashes, indent=2) + "\n")

    print("\n".join(report))
    summary(report)
    log("dependency update complete")


if __name__ == "__main__":
    try:
        main()
    except (OSError, KeyError, RuntimeError, urllib.error.URLError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
