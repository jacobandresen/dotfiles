import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        PI_CODING_AGENT_DIR=str(self.root / "agent"), DOTFILES_CODING_MODEL="qwen3.5:4b")

    def executable(self, name, script):
        path = self.bin / name
        path.write_text("#!/usr/bin/env bash\nset -eu\n" + script)
        path.chmod(0o755)

    def run_script(self, name, *args):
        return subprocess.run(["bash", str(REPO / "scripts" / name), *args],
                              env=self.env, capture_output=True, text=True, timeout=10)

    def test_setup_host_default_and_deliberate_switch_do_not_change_catalog(self):
        self.executable("ollama", 'echo "ollama test version"\n')
        self.executable("curl", '''out=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then out="$2"; shift; fi
  shift
done
if [ -n "$out" ]; then printf '%s' '{"models":[{"name":"qwen3:8b"}]}' > "$out"; fi
''')
        catalog = REPO / "pi/agent/models.json"
        before = catalog.read_bytes()
        result = self.run_script("setup-host.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        agent = self.root / "agent"
        self.assertEqual(json.loads((agent / "settings.json").read_text())["defaultModel"], "qwen3.5:4b")
        result = self.run_script("setup-host.sh", "--use-loaded")
        self.assertEqual(result.returncode, 0, result.stderr)
        models = json.loads((agent / "models.json").read_text())["providers"]["ollama"]["models"]
        self.assertEqual([m["id"] for m in models if m.get("_launch")], ["qwen3:8b"])
        self.assertEqual(before, catalog.read_bytes())

    def test_compatible_neovim_skips_network_and_installation(self):
        self.executable("nvim", 'echo "NVIM v0.12.5"\n')
        self.executable("curl", 'echo "unexpected download" >&2; exit 99\n')
        result = self.run_script("install-neovim.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("already installed", result.stdout)

    def test_neovim_download_failure_is_reported(self):
        self.executable("nvim", 'echo "NVIM v0.10.0"\n')
        self.executable("uname", 'echo x86_64\n')
        self.executable("curl", 'echo "download failed" >&2; exit 22\n')
        result = self.run_script("install-neovim.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("download failed", result.stderr)


if __name__ == "__main__":
    unittest.main()
