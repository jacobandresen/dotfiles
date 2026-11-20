"""Real pi RPC startup probe, isolated from personal configuration and models."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class PiExtensionTest(unittest.TestCase):
    @unittest.skipUnless(shutil.which("pi"), "pi is not installed")
    def test_lifecycle_and_foreground_delegation_contract(self):
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory(prefix="pi-contract-test-") as directory:
            result = subprocess.run(
                ["pi", "--mode", "rpc", "--offline", "-na", "-ne", "-ns", "-np",
                 "--provider", "github-copilot", "--model", "gpt-5.6-luna",
                 "--no-mcp", "--no-session", "-e", str(root / "tests/fixtures/pi_extension_probe.ts")],
                input='{"type":"get_commands","id":"probe"}\n', capture_output=True, text=True, timeout=30,
                cwd=directory, env={**os.environ, "PI_CODING_AGENT_DIR": directory,
                                   "NVIM_PI_STATUS": str(Path(directory) / "status.json"), "NVIM_PI_RUN": "contract",
                                   "NVIM_PI_MODEL": "github-copilot/gpt-5.6-luna"},
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("Failed to load extension", result.stderr)
            marker = Path(directory) / "contract-ok"
            self.assertTrue(marker.exists(), result.stdout + result.stderr + (
                (Path(directory) / "status.json").read_text() if (Path(directory) / "status.json").exists() else ""
            ))
            self.assertEqual(marker.read_text(), "ok")

    def test_cancelled_editor_exit_preserves_jobs(self):
        repository = Path(__file__).resolve().parents[2]
        for choice, dirty in [("1", "no"), ("2", "yes")]:
            with self.subTest(choice=choice, dirty=dirty), tempfile.TemporaryDirectory(prefix="pi-exit-test-") as directory:
                result = subprocess.run(
                    ["nvim", "--headless", "-u", "NONE", "-i", "NONE", "-l", "nvim/tests/pi_exit.lua"],
                    env={**os.environ, "PI_EXIT_TEST_DIR": directory, "PI_EXIT_CHOICE": choice, "PI_EXIT_DIRTY": dirty},
                    cwd=repository, capture_output=True, text=True, timeout=10,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual((Path(directory) / "result").read_text().strip(), "preserved")

    @unittest.skipUnless(shutil.which("pi"), "pi is not installed")
    def test_pinned_extension_loads_and_publishes_lifecycle(self):
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory(prefix="pi-extension-test-") as directory:
            status = Path(directory) / "status.json"
            environment = {
                **os.environ,
                "PI_CODING_AGENT_DIR": directory,
                "NVIM_PI_STATUS": str(status),
                "NVIM_PI_RUN": "test-run",
                "NVIM_PI_MODEL": "github-copilot/gpt-5.6-luna",
            }
            result = subprocess.run(
                ["pi", "--mode", "rpc", "--offline", "-na", "-ne", "-ns", "-np",
                 "--provider", "github-copilot", "--model", "gpt-5.6-luna",
                 "--session-id", "issue-offline-test", "--no-mcp", "-e", str(root / "pi/extension.ts")],
                input='{"type":"get_commands","id":"probe"}\n',
                text=True, capture_output=True, timeout=30, cwd=directory, env=environment,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("Failed to load extension", result.stderr)
            replies = [json.loads(line) for line in result.stdout.splitlines() if line.startswith("{")]
            reply = next(item for item in replies if item.get("id") == "probe")
            self.assertTrue(reply["success"], reply)
            names = {item["name"] for item in reply["data"]["commands"]}
            self.assertIn("subagents-guide", names)
            self.assertNotIn("run", names, "Detached slash launchers are deliberately not exposed")
            snapshot = json.loads(status.read_text())
            self.assertEqual(snapshot["run"], "test-run")
            self.assertEqual(snapshot["cwd"], directory)
            self.assertGreater(snapshot["sequence"], 0)
            self.assertEqual(snapshot["model"], "github-copilot/gpt-5.6-luna")
            self.assertNotIn("prompt", snapshot)
            restarted = subprocess.run(
                result.args, input='{"type":"get_commands","id":"probe"}\n',
                text=True, capture_output=True, timeout=30, cwd=directory, env=environment,
            )
            self.assertEqual(restarted.returncode, 0, restarted.stderr)
            next_snapshot = json.loads(status.read_text())
            self.assertGreater(next_snapshot["sequence"], snapshot["sequence"],
                               "Reload/reinitialization must not reset the accepted event sequence")


if __name__ == "__main__":
    unittest.main()
