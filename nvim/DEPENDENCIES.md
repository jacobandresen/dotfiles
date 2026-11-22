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

- **pi-agent** using its configured default model — `<leader>ap` toggles the terminal;
  `<leader>as` sends the file or selection. Its Markdown output uses the
  Retrobox palette in `themes/pi-retrobox.json`. Buffers reload on focus.
- **gh**, authenticated for the issue repository — optional, only for explicitly
  enabled GitHub integration. Local tasks need Git but no remote or GitHub account.
- **Node.js/npm** — the pinned `pi-subagents@0.89.1` dependency. Run
  `:PiIssuesSetup` once after installing this configuration. No package installation,
  issue requests, or model calls run on editor startup. Pi 1.5.2 is integration-tested.

New terminals and task sessions inherit pi-agent's model and thinking settings,
including `PI_CODING_AGENT_DIR` and project configuration. Neovim does not force a
provider or model unless explicitly set in `vim.g.pi_issues`. Resumed sessions
retain Pi's saved-session model behavior. Foreground reviewers use the model
reported by the active task session, including after a model switch.

### Local tasks by default

`Space a n` / `:PiTaskNew` opens a blank Markdown task. Write `# Task title`,
a blank line, and your own description or checklist. `:write` creates
`.tasks/001-task-title.md` in the primary Git checkout; no remote, predefined
task or agent is required. An empty title is rejected without losing the draft.
`:PiTaskNew Improve search` creates a titled file directly, with no boilerplate.
Task completion is never inferred from agent state.

`Space a i` / `:PiTasks` lists local tasks. `Ctrl-n` in the picker or `n` in the
workspace panel opens a blank task. `Ctrl-o` edits; `?` shows actions in normal
mode. `Ctrl-s` searches titles and bodies locally.
Task IDs come from filenames and must be unique; keep filenames stable.
Normal `:write` saves the task directly, with no draft publication step. You can
commit `.tasks/` deliberately or keep it untracked. Task-file edits always use the
primary checkout, even while code is edited in a separate worktree.

`util/pi_tasks.lua` provides shared repository, list, get, update and identity
operations for local tasks and GitHub issues. Worktree routing, saved sessions,
agent limits, diff review and task editing reuse the same workflow.

### Daily task workflow

| Key | Action |
| --- | --- |
| `Space a n` | Write a new local task; `:write` creates its file |
| `Space a i` | Pick local tasks; Tab selects several, Enter starts them now (base `HEAD`), `Ctrl-b` reviews / picks a base first |
| `Space a g` | Start (or focus) the task in the current task buffer or tab |
| `Space a a` | Switch task: running ones first; Enter jumps to its pi, `Ctrl-o` to its code tab |
| `Space a w` | Compact workspace panel; `1`-`9` jump to a task's pi, Enter opens code, `p` starts/focuses pi, `c` asks an idle pi to continue |
| `F6` / `Space a p` | Hide/show Pi without stopping it; F6 also works in terminal mode |
| `Space a s` | Paste file/selection context into that task's pi; Enter submits |
| `Space a r` | Paste a foreground reviewer request using the existing extension |
| `Space a v` / `:PiTaskView` | View/edit the active task; GitHub uses a local draft |
| `Space a e` / `:PiTaskEdit` | Ask its active pi-agent to revise the task file or draft |
| `Space g D` | Wide diff left, changed files right |
| `Space a q` | Confirm stopping owned agents and quit (`:PiQuit`) |

The launch review shows repository, base commit, branches and paths. Press `s`
to prepare and start, Enter to prepare without model calls, or `q` to cancel.
Local tasks use sibling `<repo>-worktrees/task-<number>/` directories and
`task/<number>` branches, based on the locally selected ref (`HEAD` by default).
GitHub issues retain `<repo>-worktrees/<number>/` and `issue/<number>`.
Matching branches are reused only after confirmation. Uncommitted
changes in the main checkout are not copied. The initial limit is three live
task agents; extra tasks are prepared, not queued for automatic execution.
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
starts another agent. Press `F6` to hide Pi directly from terminal input, including
standalone sessions opened with `Space a p`. Press `F6` again to restore it.
Use `Ctrl-\ Ctrl-n` to leave terminal input for other Neovim keys.
Use `:PiQuit` for cancellable bulk shutdown: modified files and Cancel keep agents
running. Ordinary/forced Neovim exits retain their normal semantics and stop owned
jobs on actual exit, not during a failed quit attempt. After a crash, the next
start offers lock recovery only if both recorded processes have exited.

**Extension reuse:** pi-subagents supplies the foreground reviewer/scout/worker,
tool execution, and result rendering. Neovim owns persistent task tabs and
top-level interactive pi processes because the extension's child inspectors are
not attachable Neovim terminals. Managed tabs intentionally expose only direct,
foreground, explicit-model delegation, not its detached/workflow launchers or
inspector shortcuts. Existing personal pi settings/authentication are untouched.
These workflow checks and worktrees are **not a permissions sandbox**; commands
still have the user's filesystem, credentials, network and shared-service access.

### Optional GitHub integration

GitHub integration is disabled by default. Enable it in `lua/config/options.lua`:

```lua
vim.g.pi_issues = { github_enabled = true }
```

Then use `:PiTasks github` or `:PiIssues` to select GitHub issues. Local task
selection remains the default even when GitHub is enabled. Existing GitHub
workspace metadata is retained; fetching or publishing an issue requires the
setting above. This controls task integration, not pi-agent's AI provider:
using a hosted model still requires that model's network/authentication.

In the issue picker, `Ctrl-o` opens an issue without creating a worktree or
starting an agent. In the workspace panel, `v` opens that workspace's issue.
`Space a v` / `:PiIssueView` opens the active issue as an editable local draft.
Keep `# Issue title` on the first line, a blank second line, then the Markdown
body. `:write` saves locally, not to GitHub. Drafts persist under Neovim's
pi-issues state directory, outside worktrees, and reopen without losing edits.

`Space a e` / `:PiIssueEdit` asks for revision instructions and pastes a bounded
draft-only request into the matching active pi-agent. Press Enter in pi to
submit it, then return to the draft to review its edits. This does not start
another agent or authorize publishing. Unsaved buffer edits are saved first.

From the draft, `Space a P` / `:PiIssuePublish` confirms publishing its title and
body using `gh issue edit`. Changes on GitHub since the draft was fetched block
publishing; `:PiIssueReload` explicitly confirms discarding the local draft and
fetching the current issue. No comments, labels, assignees or issue state are
changed. GitHub's CLI does not provide an atomic compare-and-update here, so
avoid simultaneous edits while publishing.

### Copy tasks between local files and GitHub

With GitHub integration enabled, `:PiTaskImport 42` reads issue 42 from the
current repository's GitHub remote and confirms creating a new local task with
the same title/body. In an active GitHub issue workspace, `:PiTaskImport` uses
that issue. Imported tasks receive a new local ID; the GitHub issue is unchanged.

Open a local task or activate its workspace, then use `:PiTaskExport`. It saves
any open task-buffer edits, shows the destination repository, and confirms
creating a **new** GitHub issue with the task's title/body. The local file,
worktree and conversation remain in place. Repeating export creates another
issue; this is an explicit copy, not automatic two-way synchronization.
Comments, labels, assignees and GitHub issue state are not copied.

Focused checks, from the repository root (no hosted model requests). `make test-pi`
runs all of them; `pi_e2e.lua` boots the real config and uses keystrokes to write tasks,
start three agents at once, queue a fourth, stop/resume, quit and restore, with a
scripted offline pi (`PI_E2E_VERBOSE=1` prints steps, `PI_E2E_KEEP=1` keeps its files).
`make test-pi-real` runs the same flow with the real pi against a local model only
(`PI_REAL_MODEL=ollama/<id>`; hosted or unpulled models are refused):

```sh
make test-pi
make test-pi-real   # opt-in: real pi + extension + your local default model (slow on CPU)
timeout 180 nvim --headless -u NONE -i NONE -l nvim/tests/pi_e2e.lua
timeout 60 nvim --headless -u NONE -i NONE -l nvim/tests/pi_issues.lua
timeout 30 nvim --headless -u NONE -i NONE -l nvim/tests/pi_layout.lua
python3 nvim/tests/pi_extension.py
timeout 30 nvim --headless -u NONE -i NONE -l nvim/tests/pi_issue_edit.lua
timeout 60 nvim --headless -u NONE -i NONE -l nvim/tests/pi_tasks.lua
timeout 30 nvim --headless -u NONE -i NONE -l nvim/tests/pi_task_copy.lua
```

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
