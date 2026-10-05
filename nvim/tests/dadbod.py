"""Run Dadbod integration checks without touching personal connections or data."""
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[2]
data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
with tempfile.TemporaryDirectory(prefix="nvim-dadbod-") as tmp:
    root = Path(tmp)
    (root / "data/nvim").mkdir(parents=True)
    (root / "data/nvim/lazy").symlink_to(data / "nvim/lazy", target_is_directory=True)
    init = root / "init.lua"
    init.write_text("vim.opt.rtp:prepend(" + repr(str(repo / "nvim")) + ")\n"
                    "require('config.lazy')\n"
                    "local config = require('lazy.core.config')\n"
                    "local plugin = require('lazy.core.plugin')\n"
                    "for _, name in ipairs({'mason.nvim', 'mason-lspconfig.nvim', 'nvim-treesitter'}) do\n"
                    "  if config.plugins[name] then\n"
                    "    plugin.values(config.plugins[name], 'opts', false).ensure_installed = {}\n"
                    "  end\n"
                    "end\n")
    database = root / "fixture.sqlite3"
    with sqlite3.connect(database) as connection:
        connection.executescript("CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT);"
                                 "INSERT INTO people VALUES (1, 'Ada'), (2, 'Grace');")
    second_database = root / "persisted.sqlite3"
    with sqlite3.connect(second_database) as connection:
        connection.execute("CREATE TABLE saved_connection (id INTEGER)")
    env = dict(os.environ, XDG_DATA_HOME=str(root / "data"),
               XDG_STATE_HOME=str(root / "state"), XDG_CACHE_HOME=str(root / "cache"),
               NVIM_LOG_FILE=str(root / "nvim.log"), DADBOD_TEST_DB=str(database),
               DADBOD_TEST_SECOND_DB=str(second_database))
    # Don't discover personal environment connections during fixture tests.
    for name in list(env):
        if name.startswith("DB_UI_") or name in ("DATABASE_URL", "DBUI_URL", "DBUI_NAME"):
            del env[name]
    def run_case(case):
        env["DADBOD_TEST_CASE"] = case
        result = subprocess.run(["nvim", "--headless", "-i", "NONE", "-u", str(init),
                                 "-c", "lua local ok, err = pcall(dofile, 'nvim/tests/dadbod.lua'); "
                                 "if not ok then print(err); vim.cmd('cquit 1') end"],
                                cwd=repo, env=env, timeout=60)
        if result.returncode:
            raise SystemExit(result.returncode)

    for case in ("direct", "connections", "integration"):
        run_case(case)

    if "--postgres" in sys.argv:
        cluster = root / "postgres"
        socket = root / "socket"
        socket.mkdir()
        subprocess.run(["initdb", "-D", str(cluster), "-A", "trust", "--no-locale"],
                       check=True, stdout=subprocess.DEVNULL)
        subprocess.run(["pg_ctl", "-D", str(cluster), "-l", str(root / "postgres.log"),
                        "-o", f"-h '' -k {socket}", "-w", "start"],
                       check=True, stdout=subprocess.DEVNULL)
        try:
            env["DADBOD_TEST_URL"] = f"postgresql:///postgres?host={socket}"
            subprocess.run(["psql", env["DADBOD_TEST_URL"], "-X", "-c",
                            "CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT);"
                            "INSERT INTO people VALUES (1, 'Ada'), (2, 'Grace');"],
                           check=True, stdout=subprocess.DEVNULL)
            # Reuse the same UI tests with fresh connection persistence.
            (root / "data/nvim/db_ui/connections.json").unlink()
            (root / "data/nvim/db_ui/fixture/saved-query.sql").unlink()
            run_case("integration")
        finally:
            subprocess.run(["pg_ctl", "-D", str(cluster), "-m", "immediate", "-w", "stop"],
                           check=True, stdout=subprocess.DEVNULL)
