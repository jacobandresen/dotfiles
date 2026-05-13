# dotfiles

My hackbox setup — [WezTerm](https://wezfurlong.org/wezterm/) and [Neovim](https://neovim.io/) configs, wired together so they share a single color scheme.


```
.wezterm.lua    — terminal
nvim/           — editor (LazyVim-based)
scripts/        — theme switcher
```

## Setup

You'll need Neovim ≥ 0.9, git, and [Terminess Nerd Font](https://www.nerdfonts.com/font-downloads) (TerminessTTF).

Clone the repo somewhere and symlink the configs into place:

```sh
git clone https://github.com/jacobandresen/dotfiles ~/dotfiles
cd ~/dotfiles

ln -sf "$(pwd)/.wezterm.lua" ~/.wezterm.lua
ln -sf "$(pwd)/nvim" ~/.config/nvim
```

Then open Neovim — [lazy.nvim](https://github.com/folke/lazy.nvim) installs everything on first launch.

## WezTerm

[WezTerm](https://wezfurlong.org/wezterm/) is a GPU-accelerated terminal written in Rust. The config leans into a deliberately minimal, retro CMD.EXE look:

- **120×40 initial window** — a bit more breathing room than the classic 80×25

- **Blinking block cursor** at 530ms
- **Tab bar and scroll bar enabled**
- **4px padding** all around for a tight, edge-to-edge feel
- **[Atelier Forest Light (base16)](https://github.com/tinted-theming/base16-schemes)** as the default color scheme

## Neovim

Built on [LazyVim](https://www.lazyvim.org/) with a curated plugin set and a custom **TurboVim** menu bar that pays tribute to [Turbo Pascal 7](https://en.wikipedia.org/wiki/Turbo_Pascal).

- **TurboVim** — a local plugin that draws a TP7-style menu bar (`<F10>` to toggle), with keyboard navigation and dropdowns wired to LSP, Telescope, and DAP actions
- **LSP** via [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) + [Mason](https://github.com/mason-org/mason.nvim): C/C++ (clangd), C# (Roslyn), Helm, YAML — auto-installed on first launch
- **Debugging** via [nvim-dap](https://github.com/mfussenegger/nvim-dap): codelldb (C/C++), netcoredbg (C#), js-debug-adapter (JS/TS)
- **Fuzzy finding** with [Telescope](https://github.com/nvim-telescope/telescope.nvim) + fzf native sorter
- **File management** with [oil.nvim](https://github.com/stevearc/oil.nvim) and [neo-tree](https://github.com/nvim-neo-tree/neo-tree.nvim)
- **AI assist** via [codecompanion.nvim](https://github.com/olimorris/codecompanion.nvim) backed by the `pi` CLI
- **Syntax** via [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
- **Folding** via [nvim-ufo](https://github.com/kevinhwang91/nvim-ufo)

See [`nvim/README.md`](nvim/README.md) for the full plugin list, TurboVim keybindings, and setup notes.

## Switching themes

```sh
bash scripts/switch-theme.sh
```

On first run it clones [tinted-theming/schemes](https://github.com/tinted-theming/schemes) (shallow, base16 only) into `~/.local/share/tinted-theming/schemes` and keeps it up to date on subsequent runs.

Pick a scheme from the fzf list. The preview pane shows the scheme name, author, color swatches for all 16 base16 slots, accent colors on the theme background, and a full hex palette reference.

Confirming a selection rewrites the `config.color_scheme` line in `~/.wezterm.lua`. If your dotfiles copy differs from the live config, the script will ask whether to sync it too. WezTerm reloads immediately; Neovim picks up the change on next start.

**Dependencies:** `git`, `fzf`, `sed`

## How WezTerm and Neovim stay in sync

Neovim reads `~/.wezterm.lua` at startup and looks for the `config.color_scheme` line. As long as the scheme name ends in `(base16)` — like `"Tokyo City Terminal Dark (base16)"` — it translates that into the matching [nvim-base16](https://github.com/RRethy/nvim-base16) name and applies it. If the file isn't there or the scheme doesn't match, it falls back to a classic Borland colorscheme.

That means you only ever set the theme in one place. To switch manually, just edit `.wezterm.lua`:

```lua
config.color_scheme = "Atelier Forest Light (base16)"
```

Any [base16 scheme](https://github.com/tinted-theming/base16-schemes) works. Or use the script above and never touch the file by hand.

## Neovim at a glance

| What | How |
|------|-----|
| Menu bar | `<F10>` (TurboVim) |
| File explorer | `<leader>e` (oil.nvim) |
| Find files | `<leader>ff` |
| Live grep | `<leader>fs` |
| Open buffers | `<leader>fb` |
| Open all folds | `zR` |
| Close all folds | `zM` |
