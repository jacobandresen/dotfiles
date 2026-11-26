# ⚓ taskbay.nvim

[![tests](https://github.com/jacobandresen/taskbay.nvim/actions/workflows/test.yml/badge.svg)](https://github.com/jacobandresen/taskbay.nvim/actions/workflows/test.yml)

```
            |    |    |                     ~ the taskbay ~
           )_)  )_)  )_)          write the orders, launch the boats,
          )___))___))___)\        review the plunder, bring it home.
         )____)____)_____)\\
       _____|____|____|____\\\__
  ~~~~~\                   /~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
```

**Run a fleet of autonomous coding agents from Neovim without letting them loose
on your checkout.**

Every agent is a pirate boat. You write its orders as a small Markdown task.
When it sails out of the taskbay it gets a Git worktree of its own, a branch of
its own, and a conversation of its own. Three boats can raid three problems at
once while you keep editing in peace. When a boat comes back, you inspect the
plunder (the diff) and decide whether it goes into the treasury (your branch).

You are the fleet captain. The boats sail on their own, but they heed the pirate
code, and nothing reaches your branch without your say.

## 🏴‍☠️ The pirate code

Every boat carries these articles in its orders (the prompt taskbay writes for it):

1. **Sail only in your own waters.** Create and change files only inside your
   worktree; resolve every relative path from it.
2. **Raid only your own target.** Implement this task and nothing else, and follow
   the repository's own instructions.
3. **Keep the log.** Work through the `- [ ]` checklist, tick items off as you go,
   and add new ones when you find them. For a local task, that checklist is the
   only part of the task file a boat may touch.
4. **No tall tales.** Run the relevant tests with a timeout and report what
   actually happened.
5. **The treasure belongs to the captain.** Never commit, merge, push, close
   issues, install dependencies or remove worktrees without asking.

The captain keeps the keys to the treasury. Committing, merging, deleting and
publishing are your actions, each one confirmed.

The code is more what you'd call *guidelines*, though. It lives in the prompt,
and worktrees are not a sandbox: agents run with your user's permissions. Sail
with agents and settings you trust.

## 🗺️ A voyage

1. **Write the orders.** `Space a n` opens a blank task. Write `# Title`, a blank
   line and the body (the template starts an `## Actions` checklist), then `:write`.
   Tasks are plain files: `.tasks/NNN-slug.md`.
2. **Launch.** `Space a w` opens the harbour, a single panel that is the hub for
   everything. Your task is a `new` row, and `Enter` launches it: taskbay
   creates `<repo>-worktrees/task-N` on branch `task/N` from `HEAD`, and the
   agent takes the helm in a tab of its own.
3. **Watch the horizon.** Each row shows its boat's status (`working`,
   `waiting`, `idle`, `no changes`, ...) and checklist progress (`2/5`).
   The panel footer shows only what the selected row can do. `d` inspects the
   plunder, `c` sends an idle boat back out, and `R` relaunches with
   rewritten orders and a fresh crew; the worktree is kept.
4. **Bring it home.** `m` stops the agent, commits the worktree and merges the
   branch into your checkout, after you confirm.

The harbour holds `max_agents` boats at sea at once (3 by default). Extra tasks
are rigged and wait at the dock for a free berth.

Prefer issues to Markdown files? Switch on the tracker integration (`Space a G`)
to import GitHub issues as tasks and publish tasks as issues.

## ⚓ Fitting out

You need:

- Neovim 0.12 or newer, and Git
- [snacks.nvim](https://github.com/folke/snacks.nvim) for the pickers and the terminal
- A crew. The default agent driver is [pi](https://github.com/earendil-works/pi);
  its status extension needs Node.js/npm once, for `:TaskbaySetup`
- Optional: [gh](https://cli.github.com), authenticated, for the GitHub integration

LazyVim is optional. When it is present, its root detection follows the task
worktree.

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "jacobandresen/taskbay.nvim",
  version = "*",   -- the latest release
  lazy = false,
  dependencies = { "folke/snacks.nvim" },
  opts = {},
}
```

lazy.nvim runs `build.lua` on install and update, which installs the pinned pi
extension with `npm ci`. With another plugin manager, run `:TaskbaySetup` once.
`:help taskbay` has the short version of everything below.

## 🎬 Watch a voyage

![taskbay demo: two tasks written, two agents at sea at once, a diff inspected, one task brought home and merged](demo/taskbay.gif)

Two tasks are written, two boats sail at once, the plunder is inspected, and one
task is brought home and merged. The voyage uses the offline scripted agent, so
every take is the same. `python3 demo/record.py` records a fresh take (needs tmux)
and `python3 demo/gif.py` turns it into this GIF (needs Pillow). To replay it in a
terminal: `asciinema play demo/taskbay.cast`.

## Why hackers like it

- **One harbour.** Every task action lives in one floating panel. There's
  nothing else to memorise; `?` shows the rest.
- **Your deck stays clean.** Boats work in their own worktrees. Your checkout
  doesn't change until you merge.
- **Plain files, no lock-in.** A task is Markdown, plus an optional
  `.tasks/NNN.json` for labels, assignees, milestone, state, relations and
  imported issue data.
- **Bring your own ships.** The agent and the issue tracker are small driver
  modules. pi and GitHub ship with taskbay; Claude Code, GitLab and others are
  one file each (see [Drivers](#drivers)).

## Keys

The rest is the ship's manual.


Global keys (configurable through `keys`, see below):

| Key | Action |
| --- | --- |
| `Space a w` | The task panel |
| `Space a n` | Write a new task |
| `Space a p` / `F6` | Start, show or hide the current tab's agent (`F6` also in terminal mode) |
| `Space a v` | The current task's text (in a task tab or task buffer) |
| `Space a s` | Send the file or selection to the agent (while one runs) |
| `Space a r` | Ask the agent for a read-only review of the task's changes |
| `Space a q` | Stop all agents and quit, after confirmation |
| `Space a G` | Turn the issue tracker integration on or off |

In the panel (`?` shows the same list):

| Key | Action |
| --- | --- |
| `Enter` / `1`-`9` | Go to the task: a new one starts, a live one shows its agent, others open their tab |
| `p` / `x` | Start or resume the agent / stop it (work is kept) |
| `c` | Ask an idle agent to continue |
| `R` | Restart in a new conversation with the current task text |
| `m` | Finish: commit, merge into your checkout, mark finished |
| `d` / `D` | Working diff / changes since the recorded base |
| `v` / `f` | Task text / fields (labels, assignees, milestone, state, relations) |
| `X` | Delete the task, its worktree, branch and session, after confirmation |
| `n` / `r` / `[` `]` / `q` | New task / refresh / page / close |
| `e` / `I` | Export the task as a new issue / import issues (tracker integration on) |

In a task buffer: `:write` saves, `Tab` flips to its fields, `Space a e` asks the
task's agent to revise the text. A tracker draft (an issue opened from the import
picker) saves locally; `Space a P` publishes it after confirmation.

## Commands

| Command | Action |
| --- | --- |
| `:Taskbay` | The task panel |
| `:TaskbayNew [title]` | Write a new task (with a title: create it at once) |
| `:TaskbayImport [number]` | Import an issue as a local task (without a number: pick) |
| `:TaskbayExport` | Publish the current task as a new issue |
| `:TaskbayReload` | Discard a tracker draft and fetch the issue again |
| `:TaskbayRemote` | Turn the issue tracker integration on or off |
| `:TaskbaySetup` | One-time setup of the agent driver |
| `:TaskbayQuit` | Stop all agents and quit, after confirmation |

## Options

`setup(opts)` stores the options in `vim.g.taskbay`. Later changes to that variable
take effect at once, except `keys`, which are mapped by `setup()`.

```lua
require("taskbay").setup({
  max_agents = 3,          -- live agents at once; more tasks are prepared and wait
  agent = "pi",            -- taskbay/agents/<agent>.lua
  remote = "github",       -- taskbay/remotes/<remote>.lua
  remote_enabled = false,  -- the tracker integration is off until enabled (Space a G)
  state_dir = vim.fn.stdpath("state") .. "/taskbay",
  keys = {                 -- any subset; hints in the UI follow these
    panel = "<leader>aw", new = "<leader>an", agent = "<leader>ap", toggle = "<F6>",
    task = "<leader>av", send = "<leader>as", review = "<leader>ar", quit = "<leader>aq",
    remote = "<leader>aG", revise = "<leader>ae", publish = "<leader>aP",
  },
  pi = {                   -- options of the pi driver
    cmd = "pi",
    args = {},             -- extra arguments, e.g. { "--theme", path, "--use-theme", "retrobox" }
    provider = nil,        -- unset: pi's configured default provider and model
    model = nil,
  },
})
```

For a statusline, `require("taskbay").statusline()` names the task tab's agent,
task and status; `require("taskbay").review()` opens the changed-files picker.

## Drivers

### Agents

An agent driver is a module `taskbay.agents.<name>` (see
[`lua/taskbay/agents/pi.lua`](lua/taskbay/agents/pi.lua)). Taskbay starts its
command in a terminal inside the task's worktree and watches a status file the
agent writes: JSON with `version = 1`, `run`, an increasing `sequence`,
`activity` (`idle`, `working`, `waiting`, `exited`), `outcome`, `cwd`,
`session`, `session_file` and `model`. The pi driver reports through its
bundled extension (`agents/pi/extension.ts`).

| Field | Purpose |
| --- | --- |
| `title` | Display name |
| `check()` | Assert the agent can start |
| `command(spec)` | argv; `spec`: `session`, `session_file` (resume), `name`, `prompt_file` (new conversations) |
| `env(status_file, run)` | Environment that tells the agent where to report |
| `session_matches(file, workspace)` | A saved session belongs to the workspace |
| `terminal()` | argv of a standalone agent outside tasks |
| `review(model)` | The read-only review request |
| `delegation` | Delegation rule appended to every task prompt |
| `install()` | Optional one-time setup (`:TaskbaySetup`) |

### Issue trackers

A tracker driver is a module `taskbay.remotes.<name>` (see
[`lua/taskbay/remotes/github.lua`](lua/taskbay/remotes/github.lua)); its name is
the `source` of the tasks it serves. Everything above the driver (import, drafts,
fields, publish, export) uses only this interface and the normalised issue shape.

| Field | Purpose |
| --- | --- |
| `title`, `glyph` | Display name and icon |
| `repository(root)` | `require("taskbay.store").checkout(root)` plus `repo` (`owner/name`), `host`, `url`, `default_branch` |
| `list(repo, query, limit)` | Open issues: `number`, `title`, `url`, `state`, `labels` |
| `get(target)` | One normalised issue |
| `update(target, title, body, changes)` | `changes`: `add_labels`, `remove_labels`, `add_assignees`, `remove_assignees`, `milestone` (`""` clears), `state` |
| `create(repo, title, body)` | A new issue; returns its target |

A normalised issue has `number`, `title`, `body`, `url`, `state` (`open` /
`closed`), `labels` and `assignees` (lists of names), `milestone` (a name or nil),
`author`, `created_at`, `updated_at`, `closed_at`, `comments` (a count) and
`raw`, the tracker's own data, which imports keep verbatim.

A GitLab driver would wrap `glab` the same way: `glab repo view`, `glab issue
list/view/update/create` with `--output json`, normalising GitLab's
`state = "opened"` to `open`. Select it with `remote = "gitlab"`.

## Tests

No boat leaves port untested: the suite runs entirely offline, with scripted
stand-ins for pi and gh, and keeps line coverage at 100%.


From the plugin directory (the scripts find the plugin from their own path, so any
working directory works):

```sh
nvim --headless -u NONE -i NONE -l tests/run.lua       # the offline suite
nvim --headless -u NONE -i NONE -l tests/coverage.lua  # the same, with line coverage
```

The unit tests load only the plugin. The end-to-end tests (`e2e.lua`,
`github.lua`) drive an embedded editor with keystrokes, booted from
`tests/minimal_init.lua` (snacks.nvim and taskbay; `TASKBAY_SNACKS` points at a
snacks.nvim checkout), with offline stand-ins for pi and gh that accept only what
the real tools accept. `real.lua` runs the same flow with the real pi and a local
model. It and the real-pi probes in `pi_extension.py` read pi's settings template
and models from `TASKBAY_PI_AGENT_DIR` (default: the dotfiles' `pi/agent`); without
them the probes are skipped. `TASKBAY_E2E_VERBOSE=1` prints the steps,
`TASKBAY_E2E_KEEP=1` keeps the test repository. Inside the dotfiles that carry the
plugin, `run.lua` also runs the end-to-end flow in their configuration
(`TASKBAY_E2E_CONFIG=dotfiles`).

## License

[MIT](LICENSE). Plunder freely; keep the notice.
