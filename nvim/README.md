# Neovim Configuration

A Neovim configuration built on LazyVim, with the pi coding agent and the local
[taskbay](taskbay/README.md) plugin for task workspaces.

## Prerequisites

Only edit files inside this directory. Do not touch files inside plugin library paths.

External tools this config expects: [DEPENDENCIES.md](DEPENDENCIES.md).

## AI Integration

Only pi-agent is available in a terminal split. New sessions use pi-agent's configured
default model, with the pinned pi-subagents extension for foreground delegation using the
active session model. Keep the AI menu and keymaps limited to pi.

## Tasks (taskbay)

[taskbay](taskbay/README.md) lives in `taskbay/` and is loaded from
`lua/plugins/ai.lua` with this config's options: three agents at most (matching
`OLLAMA_NUM_PARALLEL`), pi with the Retrobox theme, and the state directory of
the earlier pi-issues workflow, so existing workspaces keep working.

Tasks are local `.tasks/*.md` files by default and stay offline; the GitHub
integration is off until `Space a G` (or `remote_enabled = true`) turns it on.
`Space a w` is the hub: every task action is a key in its panel, and the footer
lists the ones the selected row supports.

| Key | Action |
| --- | --- |
| `Space a w` | Task panel: `Enter` starts / opens a task, `d` diff, `m` finish, `?` all keys |
| `Space a n` | Write a new task; `:write` creates it in `.tasks/` |
| `Space a p` / `F6` | Start, show or hide the current tab's pi |
| `Space a v` / `Space a s` / `Space a r` | Task text / send file or selection / reviewer request |
| `Space g D` | Changed files of the current task |
| `Space a G` | GitHub integration on / off |
| `Space a q` | Stop agents and quit |

Run the plugin's offline suite with `make test-pi`, line coverage with
`nvim --headless -u NONE -i NONE -l nvim/taskbay/tests/coverage.lua`, and the
opt-in run against the real pi and a local model with `make test-pi-real`.

## Other Keys

### Test Explorer

| Key | Action |
| --- | --- |
| `Space t s` / `:TestView` | Toggle the test tree and output panel |
| `Space t r` | Run the selected tree row, or the nearest test in code |
| `Space t t` | Run the current file and show the view |
| `Space t T` | Run tests in the current file's directory |
| `Space t l` | Run the last selection |
| `Space t S` | Stop the selected running test |
| `Space t a` | Attach to the running test's live process output |
| `Space t o` | Open the selected test's output and failure details |
| `Space t O` | Toggle the bottom output panel |
| `Space t w` | Toggle watch mode for this test file |

### Database Support (Dadbod)

Install client for databases you use: sqlite3, psql or mysql.

| Key | Action |
| --- | --- |
| `Space D u` | Open the drawer |
| `A` | Add a connection in the drawer |
| `R` | Edit connections in the drawer |
| `DBUIFindBuffer` | Assign an existing SQL buffer to a connection |
| `Space D e` | Execute the whole query buffer, or selected lines in Visual mode |
| `Space E` | Execute selected lines in Visual mode (buffer-local) |
| `Space W` | Save a scratch query |

### Text Transforms

| Key | Action |
| --- | --- |
| `<leader>ct` | Invoke text transforms on selection or buffer |

Transforms support character selections, whole-line selections and whole buffers.
Rectangular selections are rejected.

