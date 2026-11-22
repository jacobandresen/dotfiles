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
        self.agent = Path(self.work.name) / ".pi/agent"

    def test_install_keeps_auth_and_sessions_and_is_idempotent(self):
        self.agent.mkdir(parents=True)
        (self.agent / "auth.json").write_text('{"private": true}')
        (self.agent / "sessions").mkdir()
        (self.agent / "sessions/history.jsonl").write_text("history")
        (self.agent / "settings.json").write_text('{"defaultModel":"old","packages":["old"]}')
        config.install(self.agent)
        before = (self.agent / "models.json").stat().st_mtime_ns
        config.install(self.agent)
        self.assertEqual(before, (self.agent / "models.json").stat().st_mtime_ns)
        self.assertEqual((self.agent / "auth.json").read_text(), '{"private": true}')
        self.assertEqual((self.agent / "sessions/history.jsonl").read_text(), "history")
        self.assertEqual(json.loads((self.agent / "settings.json").read_text())["defaultModel"],
                         "mellum")
        self.assertEqual(json.loads((self.agent / "settings.json").read_text())["modelThinkingLevels"],
                         {"ollama/mellum": "high"})
        models = json.loads((self.agent / "models.json").read_text())["providers"]["ollama"]["models"]
        self.assertEqual([model["id"] for model in models], ["mellum", "qwen3.5:9b"])
        self.assertEqual(models[0]["contextWindow"], 16384)
        self.assertEqual(models[0]["samplingParams"]["temperature"], 0.2)
        self.assertEqual(json.loads((self.agent / "settings.json").read_text())["enabledModels"], [
            "ollama/mellum",
            "ollama/qwen3.5:9b",
            "github-copilot/gpt-6.1-sol",
            "github-copilot/claude-opus-5.5",
        ])
        self.assertTrue((self.agent / "AGENTS.md").is_symlink())

    def test_repo_or_legacy_symlink_is_rejected(self):
        with self.assertRaises(ValueError):
            config.install(config.ROOT / "pi/agent")
        self.agent.parent.mkdir()
        self.agent.symlink_to(config.ROOT / "pi/agent")
        with self.assertRaises(ValueError):
            config.install(self.agent)

    def test_dry_run_does_not_write(self):
        config.install(self.agent, dry_run=True)
        self.assertFalse(self.agent.exists())

    def test_custom_ollama_host(self):
        with patch.dict("os.environ", {"OLLAMA_HOST": "http://localhost:1234"}):
            config.install(self.agent)
        provider = json.loads((self.agent / "models.json").read_text())["providers"]["ollama"]
        self.assertEqual(provider["baseUrl"], "http://localhost:1234/v1")

    def test_template_is_authoritative_for_model_settings(self):
        source = Path(self.work.name) / "repo/pi/agent"
        source.mkdir(parents=True)
        settings = {
            "defaultProvider": "github-copilot",
            "defaultModel": "gpt-6.1-sol",
            "enabledModels": ["github-copilot/gpt-6.1-sol"],
        }
        (source / "settings.json.template").write_text(json.dumps(settings))
        (source / "models.json").write_text((config.ROOT / "pi/agent/models.json").read_text())
        with patch.object(config, "ROOT", source.parents[1]):
            config.install(self.agent)
        self.assertEqual(json.loads((self.agent / "settings.json").read_text()), settings)


if __name__ == "__main__":
    unittest.main()
