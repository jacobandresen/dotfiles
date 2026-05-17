# dotfiles

My personal [WezTerm](https://wezfurlong.org/wezterm/) and [Neovim](https://neovim.io/) setup, wired together to share a single color scheme.

```
.wezterm.lua    — terminal
nvim/           — editor (LazyVim-based)
pi/agent/       — pi coding agent config (settings, models, skills)
```

## Setup

Requirements: Neovim ≥ 0.9, git, [Terminess Nerd Font](https://www.nerdfonts.com/font-downloads) (TerminessTTF).

```sh
git clone https://github.com/jacobandresen/dotfiles ~/dotfiles
cd ~/dotfiles

ln -sf "$(pwd)/.wezterm.lua" ~/.wezterm.lua
ln -sf "$(pwd)/nvim" ~/.config/nvim
ln -sf "$(pwd)/pi/agent" ~/.pi/agent

```

Open Neovim — [lazy.nvim](https://github.com/folke/lazy.nvim) installs everything on first launch.

## Makefile

| Target | What it does |
|--------|-------------|
| `make deps` | Installs system dependencies — detects macOS (Homebrew), Arch (pacman), Ubuntu, or Debian (apt) and installs git, neovim, wezterm, ollama, and the Terminess Nerd Font |
| `make install` | Installs system dependencies then copies pi skills into place (runs `deps` + `install-skills`) |
| `make install-skills` | Copies pi skills from `pi/agent/skills/` into `~/.pi/agent/skills/` |

Run `make install` to get everything set up in one step.

## Neovim

Built on [LazyVim](https://www.lazyvim.org/) with a custom **TurboVim** menu bar that pays tribute to [Turbo Pascal 7](https://en.wikipedia.org/wiki/Turbo_Pascal).

- **TurboVim** — TP7-style menu bar (`<F10>`), dropdowns wired to LSP, Telescope, and DAP
- **LSP** via [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) + [Mason](https://github.com/mason-org/mason.nvim): C/C++ (clangd), C# (Roslyn), Helm, YAML
- **Debugging** via [nvim-dap](https://github.com/mfussenegger/nvim-dap): codelldb (C/C++), netcoredbg (C#), js-debug-adapter (JS/TS)
- **Fuzzy finding** with [Telescope](https://github.com/nvim-telescope/telescope.nvim) + fzf native sorter
- **File management** with [oil.nvim](https://github.com/stevearc/oil.nvim) and [neo-tree](https://github.com/nvim-neo-tree/neo-tree.nvim)
- **AI assist** via [codecompanion.nvim](https://github.com/olimorris/codecompanion.nvim) backed by the `pi` CLI
- **Syntax** via [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
- **Folding** via [nvim-ufo](https://github.com/kevinhwang91/nvim-ufo)

See [`nvim/README.md`](nvim/README.md) for the full plugin list, keybindings, and setup notes.

| What | How |
|------|-----|
| Menu bar | `<F10>` (TurboVim) |
| File explorer | `<leader>e` (oil.nvim) |
| Find files | `<leader>ff` |
| Live grep | `<leader>fs` |
| Open buffers | `<leader>fb` |
| Open all folds | `zR` |
| Close all folds | `zM` |

## pi agent

[pi](https://github.com/badlogic/pi) is a local-first AI assistant backed by [Ollama](https://ollama.com/). Default model: `gemma4`.

```sh
ollama pull gemma4
pi
```

Skills loaded automatically (`/skill:name`): `git-workflow`, `task-planner`, `code-agent`, `shell-scripts`, `nvim-config`, `supabase`.

## Contact

You can reach at jacob.andresen@gmail.com .

