#!/usr/bin/env python3
"""Read-only checks for the tools required by these dotfiles."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


def main():
    failed = False
    commands = ["git", "curl", "python3", "zsh", "rg", "fd", "jq", "make", "cc",
                "pkg-config", "node", "npm", "unzip", "tar", "base64", "kitty", "mc", "pi", "ollama", "lazydocker"]
    for command in commands:
        path = shutil.which(command)
        print(f"{'OK' if path else 'MISSING'} {command}")
        failed |= path is None
    nvim = shutil.which("nvim")
    version = subprocess.run([nvim, "--version"], capture_output=True, text=True).stdout if nvim else ""
    match = re.search(r"NVIM v(\d+)\.(\d+)\.(\d+)", version)
    compatible = match is not None and tuple(map(int, match.groups())) >= (0, 12, 0)
    print(f"{'OK' if compatible else 'MISSING/OLD'} Neovim >= 0.12")
    failed |= not compatible
    omz = Path(os.environ.get("ZSH", str(Path.home() / ".oh-my-zsh"))) / "oh-my-zsh.sh"
    print(f"{'OK' if omz.is_file() else 'MISSING'} Oh My Zsh")
    failed |= not omz.is_file()
    docker = shutil.which("docker")
    compose = docker and subprocess.run([docker, "compose", "version"], capture_output=True).returncode == 0
    optional = sys.platform == "darwin"
    print(f"{'OK' if compose else 'OPTIONAL' if optional else 'MISSING'} Docker + Compose")
    failed |= not optional and not compose
    print("Run make deps to install missing tools; optional language SDKs are listed in nvim/DEPENDENCIES.md.")
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
