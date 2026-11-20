# Dependencies

External tools this config expects on `$PATH`. Anything not listed here is
installed automatically by `lazy.nvim` (plugins) or Mason (LSP servers, DAP
adapters, formatters).

## Core

- **Neovim** >= 0.12 (`vim.lsp.config`, `:lsp restart`)
- **git** — plugin management, gitsigns
- **ripgrep** (`rg`) — live grep / grep word
- **BigBlueTermPlus Nerd Font Mono** — installed by `make install-fonts` for
  Neovide and the configured kitty terminal; includes Nerd Font tool icons
- **A truecolor terminal** (`COLORTERM=truecolor`) — required by the configured
  Neovim colours
- **[lazydocker](https://github.com/jesseduffield/lazydocker)** — `<leader>gd`
  opens it for containers/images/compose stacks. Installed by `make deps`.
- **git-pi** — installed by `make install`; `git-pi start <issue>` creates an
  isolated worktree and starts pi, while `<leader>gD` shows a compact diff.

## AI (`lua/plugins/ai.lua`, `lua/util/agents.lua`)

- **pi-agent** with GitHub Copilot `gpt-5.6-luna` — `<leader>ap` toggles the terminal;
  `<leader>as` sends the file or selection. Its Markdown output uses the
  Retrobox palette in `themes/pi-retrobox.json`. Buffers reload on focus.
- **gh**, authenticated for the issue repository — issue selection and task bodies.
- **Node.js/npm** — the pinned `pi-subagents@0.89.1` dependency. Run
  `:PiIssuesSetup` once after installing this configuration. No package installation,
  issue requests, or model calls run on editor startup. Pi 1.5.2 is integration-tested.

### Daily issue workflow

| Key | Action |
| --- | --- |
| `Space a i` | Pick issues; Tab selects several, Enter reviews the launch |
| `Space a w` | Compact workspace panel; Enter opens code, `p` starts/focuses pi |
| `Space a p` | Hide/show the issue's pi split without stopping it |
| `Space a s` | Paste file/selection context into that issue's pi; Enter submits |
| `Space a r` | Paste a foreground reviewer request using the existing extension |
| `Space g D` | Wide diff left, changed files right |
| `Space a q` | Confirm stopping owned agents and quit (`:PiQuit`) |

The launch review shows repository, base commit, branches and paths. Press `s`
to prepare and start, Enter to prepare without model calls, or `q` to cancel.
Workspaces use sibling `<repo>-worktrees/<issue>/` directories and `issue/<number>`
branches. Matching branches are reused only after this confirmation. Uncommitted
changes in the main checkout are not copied. The initial limit is three live
issue agents; extra issues are prepared, not queued for automatic execution.
Override it explicitly with `vim.g.pi_issues = { max_agents = 2 }` in your options.

The panel uses restrained status accents and cached file counts. `x` confirms
stopping one agent, `r` refreshes, and `?` shows help. State describes the agent,
not whether tests passed. Existing workspaces restore without starting agents;
`p` resumes the exact saved conversation, without repeating the issue prompt.
Files, branches and sessions are never automatically removed or published.

Diff labels separate staged, unstaged and untracked files. `Ctrl-g` switches
between working changes and all changes since the recorded issue base;
`Ctrl-r` refreshes, `Ctrl-f`/`Ctrl-b` scroll the preview, and `Alt-w` cycles windows.
Use the picker's `?` help for its preview-only/maximize controls. Binary files
show Git's binary summary; untracked text gets a real addition diff.

Context is a labeled buffer snapshot, including unsaved edits, bounded to 100 KB.
Sending refuses files (including symlinks) outside the selected worktree and never
starts another agent. Use `Ctrl-\ Ctrl-n` to leave terminal input for Neovim keys.
Use `:PiQuit` for cancellable bulk shutdown: modified files and Cancel keep agents
running. Ordinary/forced Neovim exits retain their normal semantics and stop owned
jobs on actual exit, not during a failed quit attempt. After a crash, the next
start offers lock recovery only if both recorded processes have exited.

**Extension reuse:** pi-subagents supplies the foreground reviewer/scout/worker,
tool execution, and result rendering. Neovim owns persistent issue tabs and
top-level interactive pi processes because the extension's child inspectors are
not attachable Neovim terminals. Managed tabs intentionally expose only direct,
foreground, explicit-model delegation, not its detached/workflow launchers or
inspector shortcuts. Existing personal pi settings/authentication are untouched.
These workflow checks and worktrees are **not a permissions sandbox**; commands
still have the user's filesystem, credentials, network and shared-service access.

Focused checks, from the repository root (no hosted model requests):

```sh
timeout 60 nvim --headless -u NONE -i NONE -l nvim/tests/pi_issues.lua
timeout 30 nvim --headless -u NONE -i NONE -l nvim/tests/pi_layout.lua
python3 nvim/tests/pi_extension.py
```

Plugin updates are explicit (`:Lazy update`); startup does not update plugins.
The generated `lazy-lock.json` is local and ignored by git.
`<leader>ff` respects ignore rules; `<leader>fI` includes ignored files.
`<leader>cF` applies a server-provided `source.fixAll` action. ESLint and
Biome LSP servers start only in projects with their respective config files.

## Debugging (`lua/plugins/dap.lua`)

- **node** — runs Mason's `js-debug-adapter` for JS/TS debugging

## Text transforms (`lua/util/transform.lua`, `<leader>ct`)

- **jq** — JSON prettify/minify/escape/unescape
- **python3** — URL/HTML encode/decode
- **base64** (coreutils) — base64 encode/decode

Transforms support character selections, whole-line selections and whole
buffers. Rectangular selections are rejected. The picker keeps the original
buffer and selection, and cancels if that buffer changes while it is open.
URL encode/decode preserves whitespace.

Check with `NVIM_LOG_FILE=/tmp/nvim-transforms.log nvim --headless -u NONE -i NONE -l nvim/tests/transforms.lua`.

## Databases (Dadbod, `<leader>D`)

Install the client for the databases you use: **sqlite3** for SQLite, **psql**
for PostgreSQL, or **mysql** for MySQL/MariaDB. Dadbod uses these executables;
Mason does not install them.

`Space D u` opens the drawer. Press `A` there to add a connection, and `R`
after editing connections. Use `:DBUIFindBuffer` to assign an existing SQL
buffer to a connection and locate it in the drawer.

`Space D e` executes the whole query buffer, or selected lines in Visual mode.
DBUI queries support `:parameters` and record the last query
(`:DBUILastQueryInfo`). Dadbod UI's buffer-local `Space E` edits bind
parameters and `Space W` saves a scratch query. Saving SQL does **not**
execute it.

Connections and saved queries live under `stdpath("data")/db_ui`, outside this
repository. Standalone SQL can
also use Dadbod's `b:db`, `g:db`, `w:db`, `t:db` or `DATABASE_URL` connection.

Run `python3 nvim/tests/dadbod.py` from the repository root to check the real
Neovim configuration and installed plugins against temporary SQLite databases.
The runner isolates connection files, cache and state, and disables unrelated
Mason/parser installation for the test session.
Add `--postgres` to repeat the workflows against a temporary PostgreSQL cluster
when `initdb`, `pg_ctl` and `psql` are installed. It listens on a private Unix
socket and is stopped and removed afterward.

## Language toolchains

Not managed by Mason; install via the language's own tooling:

- **Rust**: `cargo`/`rustc` (rustup), `rustfmt` — used by rustaceanvim and
  the `rust` formatter
- **Go**: `go` toolchain — provides `gofmt` and supports `gopls`
- **.NET SDK**: `dotnet` — required for C# projects (Roslyn/nvim-dap-cs debug
  and build)

## Mason-managed (auto-installed, see `lua/plugins/lsp.lua`)

LSP servers configured under `nvim-lspconfig` (`clangd`, `gopls`, `eslint`,
`biome`, `helm-ls` and `docker-language-server`) are installed by LazyVim.
Roslyn is installed by Mason when `roslyn-language-server` is not already executable; an existing
executable from an older Mason `roslyn` package is reused to avoid the duplicate
shim conflict. The rest are listed in the `mason.nvim` spec: `rust-analyzer`
(run by rustaceanvim), `netcoredbg`, `codelldb`, `js-debug-adapter`, `prettier`,
`black`, `isort`, `clang-format`, `goimports`, `csharpier`, plus LazyVim's own
`stylua` and `shfmt`.

Other servers you install through `:Mason` start automatically, except
`rust_analyzer`, `omnisharp` and `csharp_ls`, which are disabled so they don't
duplicate rustaceanvim and Roslyn.

`docker-language-server` needs the `yaml.docker-compose` filetype to attach
to compose files (mapped in `lua/config/options.lua`).

## Optional

- **yaml-language-server** — backs `helm_ls`'s YAML validation
  (`lua/plugins/lsp.lua`); install manually if editing Helm charts

## Performance defaults

- Roslyn compiler/analyzer diagnostics cover open files; reference code lenses are off.
- Rust uses default Cargo features and `cargo check`; `<leader>rc` runs Clippy
  in a terminal. Configure additional Cargo features per project when needed.
- Inlay hints are off by default (`<leader>uh` toggles them).
- LazyVim provides folding. Log/JSONL buffers reload on focus or buffer entry.

Use `:Lazy profile` to inspect actual plugin load times and loading triggers.
