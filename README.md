# dotfiles

My personal [Neovim](https://neovim.io/) setup.

## Setup

Requirements: Neovim ≥ 0.9, git, [Terminess Nerd Font](https://www.nerdfonts.com/font-downloads) (TerminessTTF).

Open Neovim — [lazy.nvim](https://github.com/folke/lazy.nvim) installs all vim packages on first launch.


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

[pi](https://pi.dev) is a local-first AI coding agent. This setup uses [LM Studio](https://lmstudio.ai) as the backend with **Phi-3.5 Mini** (2.2 GB) — fits comfortably in 8 GB unified memory and supports tool use for file reading, bash execution, and edits inside Neovim.

### Setup

```sh
make setup-lmstudio   # downloads Phi-3.5 Mini, disables guardrails, wires pi config
```

On macOS, LM Studio is also installed via `make deps` (`brew install --cask lm-studio`). On Linux, download the AppImage from [lmstudio.ai](https://lmstudio.ai) and run `make setup-lmstudio` after.

Start LM Studio, then run `pi`.

### Neovim integration

The `codecompanion.nvim` plugin routes `<leader>cc` / `<leader>ca` / `<leader>ci` through pi → LM Studio → Phi-3.5 Mini. Tool use (read, bash, grep, find, ls) works out of the box.

Skills loaded automatically (`/skill:name`): `git-workflow`, `task-planner`, `code-agent`, `shell-scripts`, `nvim-config`.

## Contact

You can reach me at jacob.andresen@gmail.com .
