# ⚓ taskbay.nvim

[![tests](https://github.com/jacobandresen/taskbay.nvim/actions/workflows/test.yml/badge.svg)](https://github.com/jacobandresen/taskbay.nvim/actions/workflows/test.yml)

**A harbour for autonomous coding agents in Neovim.** Every agent is a pirate boat:
it sails out of the taskbay in a Git worktree, branch and conversation of its own.
You are the fleet captain. You write the orders, inspect the plunder and decide
what reaches your branch.

![taskbay demo: two tasks written, two agents at sea at once, a diff inspected, one task brought home and merged](demo/taskbay.gif)

## 🏴‍☠️ The pirate code

Every boat's orders (its prompt) say:

1. Sail only in your own worktree.
2. Raid only your own task, and follow the repository's rules.
3. Tick off the `- [ ]` checklist as you go.
4. Run the tests and report what really happened.
5. Never commit, merge, push, close issues, install dependencies or remove worktrees.
   The treasure belongs to the captain.

It's more what you'd call *guidelines*: worktrees are no sandbox, and agents run
with your permissions.

## ⚓ Install

Neovim 0.12+, Git, [snacks.nvim](https://github.com/folke/snacks.nvim), and an agent:
[pi](https://github.com/earendil-works/pi) by default (needs npm once). For
GitHub issues you also need [gh](https://cli.github.com) (optional).

```lua
{ "jacobandresen/taskbay.nvim", version = "*", lazy = false,
  dependencies = { "folke/snacks.nvim" }, opts = {} }
```

lazy.nvim runs `build.lua`; with other managers, run `:TaskbaySetup` once.

## 🗺️ A voyage

| Key | |
| --- | --- |
| `Space a n` | Write the orders: a Markdown task with a checklist, saved by `:write` |
| `Space a w` | The harbour: one panel for everything (`?` lists its keys) |
| `Enter` | Launch: worktree `task/N` from `HEAD`, agent in its own tab |
| `d` · `c` · `R` | Inspect the diff · send it back out · relaunch with new orders |
| `m` | Bring it home: commit and merge into your checkout (confirmed) |
| `Space a p` / `F6` | Show or hide the current tab's agent |

Up to `max_agents` boats (3) sail at once; the rest wait at the dock.
`Space a G` turns on GitHub: import issues as tasks, publish tasks as issues.
Everything else is in `:help taskbay`.

## ⚙️ Options

```lua
opts = {
  max_agents = 3,
  agent = "pi",            -- lua/taskbay/agents/<name>.lua
  remote = "github",       -- lua/taskbay/remotes/<name>.lua
  remote_enabled = false,
  keys = {},               -- e.g. { panel = "<leader>tw" }; hints follow
  pi = { cmd = "pi", args = {}, provider = nil, model = nil },
}
```

## 🚢 Bring your own ships

Agents and issue trackers are driver modules. Copy
[`agents/pi.lua`](lua/taskbay/agents/pi.lua) for a new agent (Claude Code,
Codex, ...) or [`remotes/github.lua`](lua/taskbay/remotes/github.lua) for a new
tracker (GitLab via `glab`, ...). Each file documents its interface, and
`tests/remote.lua` shows a complete tracker in a few dozen lines.

## 🧪 Tests

```sh
nvim -l tests/run.lua        # offline: scripted pi and gh stand-ins
nvim -l tests/coverage.lua   # the same, failing below 100% line coverage
```

`python3 demo/record.py && python3 demo/gif.py` re-records the demo.

## License

[MIT](LICENSE). Plunder freely; keep the notice.
