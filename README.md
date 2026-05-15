# dotfiles

My personal [WezTerm](https://wezfurlong.org/wezterm/) and [Neovim](https://neovim.io/) setup, wired together to share a single color scheme.

```
.wezterm.lua    — terminal
nvim/           — editor (LazyVim-based)
scripts/        — turbo-* helper scripts (setup, theme, clean, pi, ralph, check)
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

scripts/turbo-setup.sh   # install all system dependencies
```

Open Neovim — [lazy.nvim](https://github.com/folke/lazy.nvim) installs everything on first launch.

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
scripts/turbo-pi-run          # interactive, offline mode
scripts/turbo-pi-run --continue  # resume last session
```

Skills loaded automatically (`/skill:name`): `git-workflow`, `task-planner`, `code-agent`, `shell-scripts`, `nvim-config`, `supabase`.

### Michelle

`pi/michelle.py` manages the local Ollama installation.

```sh
python pi/michelle.py <command>
```

| Command | What it does |
|---------|-------------|
| `status` | Show installed models and current `settings.json` / `models.json` config |
| `enforce` | Remove every installed model except the default, pull it if missing, and align `settings.json` + `models.json` |
| `optimize` | Detect CPU/RAM/GPU, compute optimal Ollama settings, write a systemd service override, set CPU governor to performance, and restart Ollama |
| `move-storage` | Move `/var/lib/ollama` to `/opt/ollama` and symlink back — useful when `/var/lib` is on a small partition |

```sh
python pi/michelle.py enforce --model gemma4
python pi/michelle.py optimize
```

### Turbo Ralph

`scripts/turbo-ralph.sh` is an autonomous goal-to-code orchestrator. Give it a plain-English goal; it plans and codes until done.

Designed for **small, self-contained apps in a standalone directory**. Use `--dir` to create and enter a fresh directory automatically — Ralph will refuse to run inside an existing project unless `--force` is passed.

```sh
# Recommended: target a fresh directory
scripts/turbo-ralph.sh --dir ~/projects/my-app "build a CLI todo app"

# Cap iterations
scripts/turbo-ralph.sh --dir ~/projects/my-app -n 5 "build a CLI todo app"

# Resume an interrupted session (guard skipped automatically when PLAN.md exists)
cd ~/projects/my-app && scripts/turbo-ralph.sh "build a CLI todo app"

# Override the guard for an existing directory
scripts/turbo-ralph.sh --force "add input validation to the parser"
```

It runs `/skill:task-planner` once to produce `PLAN.md`, then loops `/skill:code-agent` until all tasks are checked off or the iteration limit (default: 10) is reached. Each iteration is logged under `.ralph/`. File writes are sandboxed to the project directory; network access is blocked.

> `code-agent` currently only supports C/C++ projects.

## Scripts

All helpers are named `turbo-*` and live in `scripts/`:

| Script | What it does |
|--------|-------------|
| `turbo-setup.sh` | Installs all system dependencies (Neovim, node, ollama, …) for macOS, Arch, and Debian/Ubuntu/WSL |
| `turbo-clean.sh` | Lists or removes large files in the repo — wrapper around `scripts/large_files.lua` |
| `turbo-theme.sh` | Interactive [base16](https://github.com/tinted-theming/base16-schemes) theme switcher via fzf |
| `turbo-pi-run` | Launches the pi coding agent (interactive, offline) |
| `turbo-ralph.sh` | Autonomous goal-to-code orchestrator — see [Turbo Ralph](#turbo-ralph) |
| `turbo-check.sh` | Checks that all required dependencies are installed |

### turbo-setup.sh

Detects the host OS and installs every dependency needed to run this dotfile setup: Neovim, node/npm, ollama, the pi coding agent, and the default model.

```sh
scripts/turbo-setup.sh
```

Supported platforms: macOS (Homebrew), Arch Linux (pacman), Debian/Ubuntu/WSL (apt + upstream Ollama installer).

### turbo-clean.sh

Finds large files (≥ 1 MB by default) under the repo and either reports them or deletes them. Wraps `scripts/large_files.lua`.

```sh
scripts/turbo-clean.sh --help        # show usage
scripts/turbo-clean.sh               # list large files
scripts/turbo-clean.sh --yolo         # delete all candidates immediately
```

## Themes

```sh
bash scripts/turbo-theme.sh
```

Pick a [base16](https://github.com/tinted-theming/base16-schemes) scheme from the fzf list. The selection is written to `~/.wezterm.lua`; Neovim reads it on next start and applies the matching colorscheme automatically.


## Contact

You can reach at jacob.andresen@gmail.com .

