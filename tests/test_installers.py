import contextlib
import io
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))
import dotfiles


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        PI_CODING_AGENT_DIR=str(self.root / "agent"))

    def executable(self, name, script):
        path = self.bin / name
        path.write_text("#!/usr/bin/env bash\nset -eu\n" + script)
        path.chmod(0o755)

    def test_compatible_neovim_skips_network_and_installation(self):
        self.executable("nvim", 'echo "NVIM v0.12.5"\n')
        result = subprocess.run([sys.executable, str(REPO / "scripts/dotfiles.py"), "install-neovim"],
                                env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("already installed", result.stdout)

    def test_neovim_download_failure_is_reported(self):
        with patch.object(dotfiles.shutil, "which", return_value=None), \
             patch.object(dotfiles.platform, "machine", return_value="x86_64"), \
             patch.object(dotfiles.urllib.request, "urlretrieve", side_effect=OSError("download failed")):
            with self.assertRaisesRegex(RuntimeError, "download failed"):
                dotfiles.install_neovim(None)

    def test_bad_download_is_removed_before_installation(self):
        path = self.root / "asset"
        def download(_url, target):
            target.write_bytes(b"wrong")
        with patch.object(dotfiles.urllib.request, "urlretrieve", side_effect=download):
            with self.assertRaisesRegex(RuntimeError, "SHA-256 mismatch"):
                dotfiles.download_verified("https://example.test/asset", path, "0" * 64)
        self.assertFalse(path.exists())

    def test_matching_docker_desktop_profile_does_not_stop_app(self):
        home = self.root / "home"
        settings = home / "Library/Group Containers/group.com.docker/settings-store.json"
        settings.parent.mkdir(parents=True)
        settings.write_text('{"memoryMiB": 4096, "other": true}\n')
        profile = self.root / "docker/desktop/8gb.json"
        profile.parent.mkdir(parents=True)
        profile.write_text('{"memoryMiB": 4096, "_comment": "ignored"}\n')
        app = self.root / "Docker.app"
        app.mkdir()
        with patch.object(dotfiles, "ROOT", self.root), patch.object(dotfiles, "HOME", home), \
             patch.object(dotfiles, "DOCKER_APP", app), patch.object(dotfiles, "ram_profile", return_value="8gb"), \
             patch.object(dotfiles, "run") as command, contextlib.redirect_stdout(io.StringIO()):
            dotfiles.docker_macos(None)
            command.assert_not_called()
            self.assertFalse((settings.parent / "settings-store.json.bak").exists())
            profile.write_text('{"memoryMiB": 8192, "_comment": "ignored"}\n')
            command.return_value = subprocess.CompletedProcess([], 1)
            dotfiles.docker_macos(None)
        self.assertEqual(json.loads(settings.read_text())["memoryMiB"], 8192)
        self.assertEqual(json.loads((settings.parent / "settings-store.json.bak").read_text())["memoryMiB"], 4096)

    def test_use_model_configures_pi_without_reprobing(self):
        args = dotfiles.argparse.Namespace(dry_run=False)
        with patch.object(dotfiles.shutil, "which", return_value="/usr/bin/ollama"), \
             patch.object(dotfiles, "api_ready", return_value=True), \
             patch.object(dotfiles, "has_model", return_value=True), \
             patch.object(dotfiles, "api_json", return_value={}), \
             patch.object(dotfiles.pi_config, "main") as install, contextlib.redirect_stdout(io.StringIO()):
            dotfiles.use_model(args)
        install.assert_called_once_with([])

    def test_matching_ollama_profile_keeps_app_running(self):
        home = self.root / "home"
        database = home / "Library/Application Support/Ollama/db.sqlite"
        database.parent.mkdir(parents=True)
        with contextlib.closing(sqlite3.connect(database)) as db, db:
            db.execute("create table settings (context_length integer)")
            db.execute("insert into settings values (8192)")
        source = self.root / "ollama/ollama.env"
        source.parent.mkdir(parents=True)
        source.write_text("OLLAMA_CONTEXT_LENGTH=8192\n")
        app = self.root / "Ollama.app"
        app.mkdir()
        with patch.object(dotfiles, "ROOT", self.root), patch.object(dotfiles, "HOME", home), \
             patch.object(dotfiles, "OLLAMA_APP", app), \
             patch.object(dotfiles.shutil, "which", return_value="/usr/bin/ollama"), \
             patch.object(dotfiles, "run", return_value=subprocess.CompletedProcess([], 0)) as command, \
             patch.object(dotfiles.time, "sleep"), contextlib.redirect_stdout(io.StringIO()):
            dotfiles.ollama_macos(None)
            self.assertFalse(any(call.args[0] in ("osascript", "open") for call in command.call_args_list))
            self.assertFalse(database.with_name("db.sqlite.bak").exists())
            command.reset_mock()
            source.write_text("OLLAMA_CONTEXT_LENGTH=16384\n")
            dotfiles.ollama_macos(None)
            self.assertTrue(any(call.args[0] == "osascript" for call in command.call_args_list))
            self.assertTrue(any(call.args[0] == "open" for call in command.call_args_list))
        with contextlib.closing(sqlite3.connect(database)) as db:
            self.assertEqual(db.execute("select context_length from settings").fetchone()[0], 16384)

    def test_linux_ollama_service_uses_current_user_and_repo(self):
        with patch.object(dotfiles.platform, "system", return_value="Linux"), \
             patch.object(dotfiles, "ram_profile", return_value="8gb"), \
             patch.object(dotfiles.getpass, "getuser", return_value="tester"), \
             patch.object(dotfiles, "run") as command, contextlib.redirect_stdout(io.StringIO()):
            dotfiles.install_ollama(None)
        service = next(call.kwargs["input"] for call in command.call_args_list
                       if call.args[:2] == ("sudo", "tee"))
        self.assertIn(b"User=tester", service)
        self.assertIn(str(REPO).encode() + b"/scripts/dotfiles.py", service)
        self.assertTrue(any(call.args == ("sudo", "systemctl", "restart", "ollama")
                            for call in command.call_args_list))

    def test_existing_font_skips_installation(self):
        with patch.object(dotfiles, "run", return_value=subprocess.CompletedProcess([], 0, "Hack Nerd Font Mono", "")) as command, \
             contextlib.redirect_stdout(io.StringIO()):
            dotfiles.install_fonts(None)
        command.assert_called_once()

    def test_macos_font_install_works_without_fc_list(self):
        with patch.object(dotfiles.platform, "system", return_value="Darwin"), \
             patch.object(dotfiles.shutil, "which", return_value=None), \
             patch.object(dotfiles, "run") as command:
            dotfiles.install_fonts(None)
        command.assert_called_once_with("brew", "install", "--cask", "font-hack-nerd-font")


if __name__ == "__main__":
    unittest.main()
