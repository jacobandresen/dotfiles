# dotfiles

My personal [WezTerm](https://wezfurlong.org/wezterm/) and [Neovim](https://neovim.io/) setup, wired together to share a single color scheme.

```
.wezterm.lua    — terminal
nvim/           — editor (LazyVim-based)
pi/agent/       — pi coding agent config (settings, models, skills)
```

## Setup

Requirements: Neovim ≥ 0.9, git, [Terminess Nerd Font](https://www.nerdfonts.com/font-downloads) (TerminessTTF).

Open Neovim — [lazy.nvim](https://github.com/folke/lazy.nvim) installs all vim packages on first launch.

## Makefile

| Target | What it does |
|--------|-------------|
| `make deps` | Installs system dependencies — detects macOS (Homebrew), Arch (pacman), Ubuntu, or Debian (apt) and installs git, neovim, wezterm, ollama, and the Terminess Nerd Font |
| `make install` | Installs system dependencies then copies pi skills into place (runs `deps` + `install-skills`) |
| `make install-skills` | Copies pi skills from `pi/agent/skills/` into `~/.pi/agent/skills/` |

Run `make install` to get everything set up in one step.

## Neovim

Built on [LazyVim](https://www.lazyvim.org/).

- **LSP** via [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) + [Mason](https://github.com/mason-org/mason.nvim): C/C++ (clangd), C# (Roslyn), Helm, YAML
- **Debugging** via [nvim-dap](https://github.com/mfussenegger/nvim-dap): codelldb (C/C++), netcoredbg (C#), js-debug-adapter (JS/TS)
- **Fuzzy finding** with [Telescope](https://github.com/nvim-telescope/telescope.nvim) + fzf native sorter
- **File management** with [oil.nvim](https://github.com/stevearc/oil.nvim) and [neo-tree](https://github.com/nvim-neo-tree/neo-tree.nvim)
- **AI assist** via [codecompanion.nvim](https://github.com/olimorris/codecompanion.nvim) backed by the `pi` CLI
- **Syntax** via [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
- **Folding** via [nvim-ufo](https://github.com/kevinhwang91/nvim-ufo)

See [`nvim/README.md`](nvim/README.md) for the full plugin list, keybindings, and setup notes.

## pi agent

[pi](https://github.com/badlogic/pi) is a local-first AI assistant backed by [Ollama](https://ollama.com/). 


Skills loaded automatically (`/skill:name`): `git-workflow`, `task-planner`, `code-agent`, `shell-scripts`, `nvim-config`, `supabase`.

## Contact

You can reach me at jacob.andresen@gmail.com .

