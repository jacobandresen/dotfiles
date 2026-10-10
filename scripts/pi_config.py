#!/usr/bin/env python3
"""Install the local pi-agent configuration for Ministral 3B."""

import argparse
import json
import os
from pathlib import Path
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MODEL = "ministral-3:3b"


def write_json(path, value):
    data = json.dumps(value, indent=2) + "\n"
    if path.is_file() and not path.is_symlink() and path.read_text() == data:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(data)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def install(agent_dir, dry_run=False):
    if agent_dir.resolve().is_relative_to(ROOT) or agent_dir.is_symlink() or agent_dir.parent.is_symlink():
        raise ValueError("pi config directory must be a real directory outside this repository")
    if dry_run:
        print(f"Would configure {agent_dir} for {MODEL}")
        return
    agent_dir.mkdir(parents=True, exist_ok=True)
    instructions = agent_dir / "AGENTS.md"
    if not instructions.exists() and not instructions.is_symlink():
        instructions.symlink_to(ROOT / "pi/agent/AGENTS.md")
    skills = agent_dir / "skills"
    if skills.is_symlink() and skills.resolve() == ROOT / "pi/agent/skills":
        skills.unlink()
    settings = json.loads((ROOT / "pi/agent/settings.json.template").read_text())
    models = json.loads((ROOT / "pi/agent/models.json").read_text())
    host = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434")
    if not host.startswith(("http://", "https://")):
        host = "http://" + host
    models["providers"]["ollama"]["baseUrl"] = host.rstrip("/") + "/v1"
    write_json(agent_dir / "settings.json", settings)
    write_json(agent_dir / "models.json", models)
    print(f"pi-agent: {MODEL}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent-dir", type=Path, default=Path(os.environ.get("PI_CODING_AGENT_DIR", Path.home() / ".pi/agent")))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    try:
        install(args.agent_dir.expanduser().absolute(), args.dry_run)
    except (OSError, ValueError) as error:
        parser.exit(1, f"pi config failed: {error}\n")


if __name__ == "__main__":
    main()
