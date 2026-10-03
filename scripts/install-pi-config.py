#!/usr/bin/env python3
"""Install shared Pi resources while keeping settings and models host-local."""
import argparse
import json
import os
from pathlib import Path
import shutil
import tempfile

REPO = Path(__file__).resolve().parent.parent


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, indent=2)
            stream.write("\n")
        os.replace(name, path)  # replaces a symlink rather than writing through it
    finally:
        if os.path.exists(name):
            os.unlink(name)


def install(agent_dir, dry_run=False):
    home = Path.home()
    legacy = home / ".pi"
    migrate = agent_dir == legacy / "agent" and legacy.is_symlink()
    if migrate and legacy.resolve() != REPO / "pi":
        raise ValueError(f"{legacy} points to another installation; refusing to replace it")
    if not migrate and agent_dir.resolve().is_relative_to(REPO):
        raise ValueError("Pi host configuration must live outside the dotfiles repository")
    if dry_run:
        print(f"Would install host-local Pi config at {agent_dir}")
        if migrate:
            print(f"Would preserve the legacy {legacy} symlink as a backup and copy its data")
        return

    if migrate:
        stage = Path(tempfile.mkdtemp(prefix=".pi-migrate-", dir=home))
        backup = home / ".pi.dotfiles-link.bak"
        while backup.exists() or backup.is_symlink():
            backup = backup.with_name(backup.name + ".bak")
        try:
            shutil.copytree(legacy.resolve(), stage, dirs_exist_ok=True, symlinks=True)
            # A nested agent symlink must also be detached before editing.
            if (stage / "agent").is_symlink():
                source = (stage / "agent").resolve()
                (stage / "agent").unlink()
                shutil.copytree(source, stage / "agent", symlinks=True)
            # These copied resources are identical to the shared sources.
            for resource in ("AGENTS.md", "skills"):
                copied = stage / "agent" / resource
                if copied.is_symlink() or copied.is_file():
                    copied.unlink()
                elif copied.is_dir():
                    shutil.rmtree(copied)
                copied.parent.mkdir(parents=True, exist_ok=True)
                copied.symlink_to(REPO / "pi" / "agent" / resource)
            legacy.rename(backup)
            try:
                stage.rename(legacy)
            except Exception:
                backup.rename(legacy)
                raise
            print(f"Preserved legacy Pi link at {backup}; runtime data copied to {legacy}")
        finally:
            if stage.exists():
                shutil.rmtree(stage)

    agent_dir.mkdir(parents=True, exist_ok=True)
    for resource in ("AGENTS.md", "skills"):
        target = agent_dir / resource
        if not target.exists() and not target.is_symlink():
            target.symlink_to(REPO / "pi" / "agent" / resource)
    for filename, seed in (("settings.json", "settings.json.template"), ("models.json", "models.json")):
        target = agent_dir / filename
        if target.is_symlink():
            atomic_json(target, json.loads(target.read_text()))
        elif not target.exists():
            atomic_json(target, json.loads((REPO / "pi" / "agent" / seed).read_text()))
    print(f"Pi settings and models are local to {agent_dir}")


def configure(agent_dir, model_name, api):
    settings_path, models_path = agent_dir / "settings.json", agent_dir / "models.json"
    settings = json.loads(settings_path.read_text())
    catalog = json.loads(models_path.read_text())
    shared = json.loads((REPO / "pi/agent/models.json").read_text())
    provider = catalog.setdefault("providers", {}).setdefault("ollama", {})
    models = provider.setdefault("models", [])
    for seed in shared["providers"]["ollama"]["models"]:
        if not any(model.get("id") == seed["id"] for model in models):
            models.append(seed)
    for model in models:
        model.pop("_launch", None)
    selected = next((model for model in models if model.get("id") == model_name), None)
    if selected is None:
        selected = {"id": model_name, "input": ["text"], "name": f"{model_name} (via Ollama)",
                    "contextWindow": 16384, "maxTokens": 4096}
        models.insert(0, selected)
    selected["_launch"] = True
    provider.update(api="openai-completions", apiKey="not-needed", baseUrl=api.rstrip("/") + "/v1")
    provider.setdefault("compat", {"supportsDeveloperRole": False, "supportsReasoningEffort": False})
    settings.update(defaultModel=model_name, defaultProvider="ollama")
    for path, value in ((models_path, catalog), (settings_path, settings)):
        if json.loads(path.read_text()) != value:
            atomic_json(path, value)
    print(f"Pi launch model: {model_name} (host-local)")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent-dir", type=Path, default=Path(os.environ.get("PI_CODING_AGENT_DIR", Path.home() / ".pi/agent")))
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--model")
    parser.add_argument("--api", default="http://127.0.0.1:11434")
    args = parser.parse_args()
    try:
        agent_dir = args.agent_dir.expanduser().absolute()
        install(agent_dir, args.dry_run)
        if args.model:
            if args.dry_run:
                print(f"Would select {args.model} in host-local settings and models")
            else:
                configure(agent_dir, args.model, args.api)
    except (OSError, ValueError) as error:
        parser.exit(1, f"Pi config installation failed: {error}\n")


if __name__ == "__main__":
    main()
