import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/pi_config.py"
spec = importlib.util.spec_from_file_location("pi_config", SCRIPT)
config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config)


class PiConfigTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        root = Path(self.work.name)
        self.home, self.repo = root / "home", root / "repo"
        self.home.mkdir()
        shared = self.repo / "pi/agent"
        (shared / "skills").mkdir(parents=True)
        (shared / "skills/test.md").write_text("shared skill")
        (shared / "AGENTS.md").write_text("shared instructions")
        self.catalog = {"providers": {"ollama": {"compat": {"supportsDeveloperRole": False}, "models": [
            {"id": "small", "contextWindow": 8192, "maxTokens": 1024},
            {"id": "large", "contextWindow": 16384, "maxTokens": 4096},
        ]}}}
        (shared / "models.json").write_text(json.dumps(self.catalog))
        (shared / "settings.json.template").write_text(json.dumps({"theme": "dark", "defaultModel": "small"}))
        self.addCleanup(patch.stopall)
        patch.object(config, "REPO", self.repo).start()
        patch.object(Path, "home", return_value=self.home).start()
        self.agent = self.home / ".pi/agent"

    def test_new_install_and_switch_are_local_and_idempotent(self):
        config.install(self.agent)
        config.configure(self.agent, "small", "http://localhost:11434")
        self.assertFalse((self.home / ".pi").is_symlink())
        self.assertTrue((self.agent / "skills").is_symlink())
        settings = json.loads((self.agent / "settings.json").read_text())
        settings["theme"] = "custom"
        config.atomic_json(self.agent / "settings.json", settings)
        config.configure(self.agent, "large", "http://localhost:11434")
        before = (self.agent / "models.json").stat().st_mtime_ns
        config.configure(self.agent, "large", "http://localhost:11434")
        self.assertEqual(before, (self.agent / "models.json").stat().st_mtime_ns)
        models = json.loads((self.agent / "models.json").read_text())["providers"]["ollama"]["models"]
        self.assertEqual([m["id"] for m in models if m.get("_launch")], ["large"])
        self.assertEqual(models[1]["contextWindow"], 16384)
        self.assertEqual(json.loads((self.agent / "settings.json").read_text())["theme"], "custom")
        self.assertEqual(json.loads((self.repo / "pi/agent/models.json").read_text()), self.catalog)

    def test_legacy_link_migration_preserves_runtime_and_auth(self):
        shared = self.repo / "pi/agent"
        (shared / "sessions").mkdir()
        (shared / "sessions/history.jsonl").write_text("history")
        (shared / "auth.json").write_text('{"test":"private"}')
        (shared / "auth.json").chmod(0o600)
        (shared / "settings.json").write_text('{"theme":"custom"}')
        (self.home / ".pi").symlink_to(self.repo / "pi")
        config.install(self.agent)
        config.configure(self.agent, "small", "http://localhost:11434")
        self.assertFalse((self.home / ".pi").is_symlink())
        self.assertTrue((self.home / ".pi.dotfiles-link.bak").is_symlink())
        self.assertEqual((self.agent / "sessions/history.jsonl").read_text(), "history")
        self.assertEqual((self.agent / "auth.json").read_text(), '{"test":"private"}')
        self.assertEqual((self.agent / "auth.json").stat().st_mode & 0o777, 0o600)
        self.assertEqual((shared / "settings.json").read_text(), '{"theme":"custom"}')
        self.assertEqual(json.loads((shared / "models.json").read_text()), self.catalog)
        self.assertTrue((self.agent / "AGENTS.md").is_symlink())

    def test_nested_legacy_link_migration_detaches_agent(self):
        shared = self.repo / "pi/agent"
        (shared / "sessions").mkdir()
        (shared / "sessions/history.jsonl").write_text("history")
        (shared / "auth.json").write_text('{"test":"private"}')
        (self.home / ".pi").mkdir()
        self.agent.symlink_to(shared)

        config.install(self.agent)

        self.assertFalse(self.agent.is_symlink())
        self.assertEqual((self.agent / "sessions/history.jsonl").read_text(), "history")
        self.assertEqual((self.agent / "auth.json").read_text(), '{"test":"private"}')
        self.assertTrue((self.agent / "AGENTS.md").is_symlink())
        self.assertTrue((self.agent / "skills").is_symlink())

    def test_dry_run_does_not_create_config_or_migrate(self):
        config.install(self.agent, dry_run=True)
        self.assertFalse((self.home / ".pi").exists())
        (self.home / ".pi").symlink_to(self.repo / "pi")
        config.install(self.agent, dry_run=True)
        self.assertTrue((self.home / ".pi").is_symlink())
        self.assertFalse((self.home / ".pi.dotfiles-link.bak").exists())

    def test_direct_repo_config_is_rejected(self):
        with self.assertRaises(ValueError):
            config.install(self.repo / "pi/agent")

    def test_symlinked_models_are_detached_without_editing_catalog(self):
        self.agent.mkdir(parents=True)
        (self.agent / "models.json").symlink_to(self.repo / "pi/agent/models.json")
        config.install(self.agent)
        config.configure(self.agent, "new-model", "http://custom-host:11434")
        self.assertFalse((self.agent / "models.json").is_symlink())
        self.assertEqual(json.loads((self.repo / "pi/agent/models.json").read_text()), self.catalog)
        provider = json.loads((self.agent / "models.json").read_text())["providers"]["ollama"]
        self.assertEqual(provider["baseUrl"], "http://custom-host:11434/v1")
        self.assertEqual(sum(bool(m.get("_launch")) for m in provider["models"]), 1)

    def test_existing_web_search_package_is_pinned(self):
        self.agent.mkdir(parents=True)
        (self.agent / "settings.json").write_text(json.dumps({"theme": "custom", "packages": ["npm:@ollama/pi-web-search", "npm:other@1.0.0"]}))
        config.install(self.agent)
        settings = json.loads((self.agent / "settings.json").read_text())
        self.assertEqual(settings["theme"], "custom")
        self.assertEqual(settings["packages"], ["npm:@ollama/pi-web-search@0.0.5", "npm:other@1.0.0"])


if __name__ == "__main__":
    unittest.main()
