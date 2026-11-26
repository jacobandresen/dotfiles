# Dependencies

External tools this config expects on `$PATH`. Anything not listed here is
installed automatically by `lazy.nvim` (plugins) or Mason (LSP servers, DAP
adapters, formatters).

## Core

- **Neovim** >= 0.12 (`vim.lsp.config`, `:lsp restart`)
- **git** — plugin management, gitsigns
- **ripgrep** (`rg`) — live grep / grep word
- **Hack Nerd Font Mono** — installed by `make install-fonts` for
  Neovide and the configured kitty terminal; includes Nerd Font tool icons
- **A truecolor terminal** (`COLORTERM=truecolor`) — required by the configured
  Neovim colours
- **[lazydocker](https://github.com/jesseduffield/lazydocker)** — `<leader>gd`
  opens it for containers/images/compose stacks. Installed by `make deps`.
- **git-pi** — installed by `make install`; `git-pi start <issue>` creates an
  isolated worktree and starts pi, while `<leader>gD` shows a compact diff.

## AI (`lua/plugins/ai.lua`, `taskbay/`)

- **minuet-ai.nvim** with the local Ollama `qwen2.5-coder:1.5b-base` FIM model
  — inline ghost-text completions in all buffers. `<A-a>` accepts the
  suggestion, `<A-l>` one line, `<A-w>` one word, `<A-[>`/`<A-]>` cycle,
  `<A-e>` dismisses. `make use-model` pulls and warms the model.
- **pi-agent** using its configured default model — `<leader>ap` toggles the terminal;
  `<leader>as` sends the file or selection. Its Markdown output uses the
  Retrobox palette in `themes/pi-retrobox.json`. Buffers reload on focus.
- **Node.js/npm** — the pinned `pi-subagents` dependency of taskbay's pi driver.
  Run `:TaskbaySetup` once after installing this configuration. No package
  installation, issue requests or model calls run on editor startup.
- **gh**, authenticated for the issue repository — optional, only for the explicitly
  enabled GitHub integration. Local tasks need Git but no remote or GitHub account.

Task workspaces (write tasks, run agents in worktrees, review, merge, GitHub
import/publish) are the local [taskbay](taskbay/README.md) plugin; its README
documents the workflow, keys, options and drivers. New terminals and task
sessions inherit pi-agent's model and thinking settings, including
`PI_CODING_AGENT_DIR`; taskbay forces no provider or model unless its `pi`
options set one. Worktrees are not a permissions sandbox: agents keep the user's
filesystem, credentials and network access.

Plugin updates are explicit (`:Lazy update`); startup does not update plugins.
The generated `lazy-lock.json` is local and ignored by git.
`<leader>ff` respects ignore rules; `<leader>fI` includes ignored files.
`<leader>cF` applies a server-provided `source.fixAll` action. ESLint and
Biome LSP servers start only in projects with their respective config files.

## Debugging (`lua/plugins/dap.lua`)

- **node** — runs Mason's `js-debug-adapter` for JS/TS debugging

## Test Explorer (`lua/plugins/testing.lua`)

[Neotest](https://github.com/nvim-neotest/neotest) provides an extensible,
VS Code-style test sidebar on the left, status signs beside test definitions,
and an output panel below the code on the right. The full-height sidebar uses
subtle background contrast, compact headers and native status highlights.
Only one sidebar is open per tab: opening Test Explorer, File Explorer or Dadbod
closes the other two. Other tabs, running tests and SQL query buffers are
unaffected. Neotest loads only when a test command is used.
Opening the view discovers tests; it does not execute them or enable watch mode.
Discovery searches test files recursively and resolves their project manifests,
including separate backend and frontend repositories below one workspace.
C# solutions, JS/TS runner roots, Python projects and Cargo crates
appear together in the same tree; individual test files do not need to be open.
For example, `:TestView ~/Projects/KAS` includes deeply nested backend unit
projects and frontend packages. `:TestView!` rescans the current directory for
new projects; `:TestView! ~/Projects/KAS` rescans that workspace.
C# discovery reads source attributes through Treesitter; no discovery host or
additional C# helper program is installed.

| Key | Action |
| --- | --- |
| `Space t s` / `:TestView` | Toggle the test tree and output panel |
| `Space t r` | Run the selected tree row, or the nearest test in code |
| `Space t t` | Run the current file and show the view |
| `Space t T` | Run tests in the current file's directory |
| `Space t l` | Rerun the last selection |
| `Space t S` | Stop the selected running test |
| `Space t a` | Attach to the running test's live process output |
| `Space t o` | Open the selected test's output and failure details |
| `Space t O` | Toggle the bottom output panel |
| `Space t w` | Explicitly toggle watch mode for this test file |

In the tree, Enter expands a group; `r` or `Space t r` runs it, `u` or
`Space t S` stops it, `i` opens its
source, `o` shows its output, `a` attaches to a running process, and `?` shows
all controls. `m` marks tests and `R` runs the marked selection. Running,
passed, failed, and skipped tests use Neotest's native VS Code-style symbols
and highlights. The statusline shows event-backed running/failure/pass counts.
The bottom panel follows live stdout for CLI test runs and retains the final
output. `a` focuses the selected running test's output; `o` shows results.
It is a normal read-only text buffer, not a terminal; ANSI controls are removed,
and output is bounded to the last 1 MiB with an explicit truncation marker.
This avoids a crash in terminal output on the installed Neovim development
build. No plugin library files are patched. Neither hiding the view nor
switching tabs cancels a test.

Project headers and directory rows are runnable, not just individual tests.
Selecting `KAS` and pressing `r` or `Space t r` runs all discovered unit tests
below that folder across C# and JavaScript/TypeScript adapters. Selecting a
nested folder limits execution to that folder. Discovery finishes before a
folder run starts; roots without tests are skipped. Language/project roots
run sequentially, while each runner retains its own internal parallelism.
`Space t l` repeats the whole folder selection. Stopping the selected folder
stops its active tests and prevents remaining roots from starting.

| Language | Adapter | External tools |
| --- | --- | --- |
| C# | `Issafalcon/neotest-dotnet` | Existing .NET SDK; MSTest/xUnit/NUnit |
| Python | `nvim-neotest/neotest-python` | Python and pytest, or Python's unittest runner; local virtual environments are detected |
| JavaScript / TypeScript | `marilari88/neotest-vitest`, `nvim-neotest/neotest-jest` | Node and the project's installed Vitest/Jest |
| Rust | Existing `mrcjkb/rustaceanvim` Neotest adapter | Cargo, rustc and rust-analyzer; no separate adapter or cargo-nextest is required |

Rust reuses rustaceanvim's discovery, Cargo commands and result parsing.
Discovery loads Rust sources in hidden buffers and starts the existing language
server when needed; opening each source file manually is unnecessary.

The Python, C#, JavaScript, TypeScript and TSX Treesitter parsers are managed
by the existing language configuration. JS/TS roots follow the closest runner
configuration, including parent monorepo configurations instead of a package's
unrelated `package.json`. Dependencies must already be installed; test commands
do not invoke `npx` downloads. Generated files, virtual environments and
directories named `e2e`, `integration` or ending in `IntegrationTests` are
excluded from automatic discovery. This is a unit-test view, not an E2E runner.

The community .NET adapter is extended in Lua to run the selected test methods
with the existing `dotnet test` CLI, including the platform runner selected in
KAS' `global.json`. Results are read from TRX files. No Microsoft source code,
SDK helpers, or additional C# programs are added. Each command uses the captured
test project, independently of Roslyn's selected solution or another issue tab.
Watch is adapter-dependent. Use the existing project DAP workflow for debugging.
Standalone scripts and Node's builtin `node --test` runner are not converted
into Vitest/pytest tests.

To extend this view, add a Neotest adapter dependency and an adapter entry in
`lua/plugins/testing.lua`; the same tree, statusline, output and controls apply.

Run the attached-UI integration checks from the repository root:

```sh
timeout 160 nvim --headless -u NONE -i NONE -l nvim/tests/testing.lua
NVIM_TEST_KAS="$HOME/Projects/KAS" timeout 360 nvim --headless -u NONE -i NONE -l nvim/tests/testing.lua
```

The first command uses disposable Python tests, including a deliberate failure,
skip, unittest case and cancellation, plus two dependency-free Rust crates,
including sibling test modules and a deliberate Rust failure.
It exercises all six sidebar transitions, reused buffers and unsaved SQL.
It also runs selected tree tests, project headers and a mixed Python/Rust
folder, including whole-folder rerun and cancellation.
The second additionally discovers KAS' backend/frontend tests together and runs
existing JavaScript, TypeScript and C# unit tests through the real adapters.
The KAS-folder shortcut is checked against every discovered C#/JS/TS test
with an execution recorder; the full KAS suite is not launched by this check.
KAS sources are not changed; runners may update their usual build/cache files.
No integration/E2E tests, database services or application servers are started.

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
