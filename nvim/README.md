# Neovim Configuration with Pi-Agent Integration

This is a Neovim configuration built on LazyVim. It integrates the pi-agent coding assistant and task management system.

## Prerequisites

Only edit files inside this directory. Do not touch files inside plugin library paths.

External tools this config expects: [DEPENDENCIES.md](DEPENDENCIES.md).

## AI Integration

Only pi-agent is available in a terminal split. New sessions use pi-agent's configured default model, with the pinned pi-subagents extension for foreground delegation using the active session model.

Keep the AI menu and keymaps limited to pi.

Task workflows default to local `.tasks/*.md` files. GitHub operations require `vim.g.pi_issues.github_enabled = true`; keep local task paths offline.

## Workspace and Task Management via Pi-Agent

### Task System

Local tasks are managed in the `.tasks/` directory as a pair of files:
- `NNN-slug.md` — the Task tab: `# Title`, a blank line, Markdown body (nothing else)
- `NNN.json` (optional metadata sidecar) — the Fields tab's storage: edited fields (`labels`, `assignees`, `milestone`, `state`, `relations`) plus the verbatim snapshot of imported GitHub issues (`issue`) and the source `origin`

```json
{"labels":["bug","cli"],"assignees":["jacob"],"milestone":"v1","state":"open",
 "relations":[{"kind":"blocked_by","target":"github.com/owner/repo#17"}],
 "origin":"github.com/owner/repo#42",
 "issue":{"assignees":[],"author":{"login":"jacob"},"body":"...","comments":[...],
          "labels":[],"milestone":{...},"number":42,"state":"open","title":"...","url":"..."}}
```

The sidecar is a plain, editable JSON file. Importing a GitHub issue (`:PiTaskImport`) writes the entire `gh issue view` snapshot into `issue`, so the original data is always available locally and nothing is dropped; editing the title, body or Fields tab never rewrites the snapshot.

Tasks run in Git worktrees branched from a commit, so a freshly initialised repository needs a first commit before a task can start.

### Key Actions and Shortcuts

#### Task Management

| Key | Action |
| --- | --- |
| `Space a n` | Write a new local task; `:write` creates its file in `.tasks/` |
| `Space a i` | Pick local tasks; Tab selects several, Enter starts them now (base `HEAD`), `Ctrl-b` reviews / picks a base first |
| `Space a g` | Start (or focus) the task in the current task buffer or tab |
| `Space a R` / `:PiTaskRestart` | Restart the task with its current description in a new conversation; the worktree is kept (dashboard: `R`). Resuming with `p` after an edit sends the updated task into the existing conversation instead |
| `Space a m` / `:PiTaskFinish` | Finish the task: stops pi if it is still running, commits the worktree's changes, merges its branch into the main checkout's branch after confirmation, and marks it finished (dashboard: `m`, also works from the task text tab) |
| `Space a a` | Switch task: running ones first; Enter jumps to its pi, `Ctrl-o` to its code tab |
| `Space a w` | Compact workspace panel exposing every task command, including written tasks not started yet (`new`); rows carry Nerd Font status glyphs (working, waiting, idle, finished, ...); unfinished tasks come first, finished ones are dimmed below; `1`-`9` jump to a task's pi (or start a `new` one), Enter opens code, `p` starts/focuses pi, `c` asks an idle pi to continue, `v` views the task, `f` its fields, `E` asks pi to revise the text, `e` exports to GitHub, `I` imports an issue, `a` switches tasks, `Q` quits pi, `[` / `]` page when the list overflows |
| `Space a p` | Hide/show Pi without stopping it; F6 also works in terminal mode |
| `Space a s` | Paste file/selection context into that task's pi; Enter submits |
| `Space a r` | Paste a foreground reviewer request using the existing extension |
| `Space a v` / `:PiTaskView` | View/edit the active task (the Task tab: title, body, relations) |
| `Tab` (in a task buffer) / `Space af` / `:PiTaskFields` | Flip between the Task and Fields tabs: Fields edits labels, assignees, milestone, state, relations; shows read-only author, dates, comments, url |
| `Space a e` / `:PiTaskEdit` | Ask its active pi-agent to revise the task file or draft |
| `Space g D` | Wide diff left, changed files right |
| `Space a q` | Confirm stopping owned agents and quit (`:PiQuit`) |

#### Pi-Agent Controls

| Key | Action |
| --- | --- |
| `F6` / `Space a p` | Hide/show Pi without stopping it; F6 also works in terminal mode |
| `Space a s` | Paste file/selection context into that task's pi; Enter submits |
| `Space a r` | Paste a foreground reviewer request using the existing extension |

#### GitHub Integration (Optional)

Enable in `lua/config/options.lua`:
```lua
vim.g.pi_issues = { github_enabled = true }
```

| Key | Action |
| --- | --- |
| `Space a G` / `:PiTaskGithub` | Enable / disable the GitHub integration for the session |
| `:PiTasks github` | Select GitHub issues |
| `Space a v` / `:PiTaskView` | Open the active issue as an editable local draft (same command as local tasks) |
| `Space a e` / `:PiTaskEdit` | Ask for revision instructions and pastes a bounded draft-only request into the matching active pi-agent |
| `Space a P` / `:PiTaskPublish` | Publish the draft's title and fields using `gh issue edit` |
| `:PiTaskReload` | Discard the local draft after confirmation and reload the GitHub issue |
| `:PiTaskDiff` / dashboard `d` `D` | Working diff or (with `issue`) the changes since the recorded base |
| `:PiTaskImport` / dashboard `I` | Pick from the repository's open GitHub issues; Enter copies the selected issue(s) into new local tasks, storing the full issue snapshot (labels, assignees, milestone, state, comments, dates) verbatim in `.tasks/NNN.json`'s `issue` key. `:PiTaskImport 42` imports a specific number without the picker |
| `:PiTaskExport` | Save task and create a new GitHub issue |

GitHub drafts keep a full issue snapshot in `baseline.json` under the state directory, so locally editing or publishing a draft never drops information from the original issue. Fields edited in the Fields tab are stored as an overlay (`fields` in `baseline.json`) and, on publish, only their diffs are pushed via `gh issue edit` (`--add-label`, `--remove-label`, `--add-assignee`, `--remove-assignee`, `--milestone`, `--state`).

#### Test Explorer

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

#### Database Support (Dadbod)

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

#### Text Transforms

| Key | Action |
| --- | --- |
| `<leader>ct` | Invoke text transforms on selection or buffer |

Transforms support character selections, whole-line selections and whole buffers.
Rectangular selections are rejected.

## Task Workflow Details

### Workspace Panel (`Space a w`)
- `1`-`9` jump to a task's pi (or start a `new` one)
- `Enter` opens code
- `p` starts/focuses pi
- `c` asks an idle pi to continue

### Pi-Agent Interaction
- Pi-agent is toggled with `Space a p` or `F6`
- Context is sent to pi-agent via `Space a s` (paste file/selection)
- Pi-agent can revise tasks with `Space a e` / `:PiTaskEdit`
- Tasks run in isolated Git worktrees
- Each task gets its own pi-agent session
- Maximum of three live task agents by default (configurable via `vim.g.pi_issues = { max_agents = 2 }`)

### Local Task Lifecycle
1. Create task with `Space a n` (the template includes an `## Actions` checklist)
2. Task is saved to `.tasks/` directory
3. Start task with `Space a g` or `Space a a`
4. Pi-agent works through the task's Actions checklist, checking items off in the task file; the workspace row shows progress (`2/5`)
5. Task can be restarted with `Space a R` — a restarted agent is told to inspect the worktree and pick up where the previous conversation left off
6. Task can be stopped with `Space a q`

### GitHub Task Integration
1. Enable GitHub integration in `options.lua` (or toggle with `Space a G`)
2. Use `:PiTasks github` to select issues
3. Import GitHub issue to local task with `:PiTaskImport`
4. Export local task to GitHub issue with `:PiTaskExport`

GitHub commands stay visible everywhere but are contextual: when the integration
is off they point to `Space a G` instead of failing.

## Configuration

Task behavior is controlled by:
- `.tasks/` directory for local tasks
- Git worktrees for task isolation
- Pi-agent for AI assistance
- LazyVim for plugin management

Run tests to verify setup:
```sh
make test-pi
make test-pi-real   # opt-in: real pi + extension + your local default model
timeout 180 nvim --headless -u NONE -i NONE -l nvim/tests/pi_e2e.lua
```
