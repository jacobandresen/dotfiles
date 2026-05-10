# dotfiles

My hackbox setup — [WezTerm](https://wezfurlong.org/wezterm/) and [Neovim](https://neovim.io/) configs, wired together so they stay in sync.

Suggestions and PRs are welcome. Feel free to [open an issue](https://github.com/jacobandresen/dotfiles/issues) if you spot something broken or have ideas.

```
.wezterm.lua    — terminal
nvim/           — editor (LazyVim-based)
```

## WezTerm

[WezTerm](https://wezfurlong.org/wezterm/) is a GPU-accelerated terminal emulator and multiplexer written in Rust. The config here goes for a deliberately minimal, retro CMD.EXE aesthetic:

- **80×25 initial window** — classic terminal dimensions
- **Andale Mono / Courier New** font stack at 14pt
- **Blinking block cursor** at 530ms — matches the old `CMD.EXE` feel
- **No tab bar, no scroll bar** — just title bar + resize border
- **Tight 4px padding** on all sides for edge-to-edge text
- **[darkmoss (base16)](https://github.com/tinted-theming/base16-schemes)** color scheme by default

Any [base16 scheme](https://github.com/tinted-theming/base16-schemes) works — change one line to switch both WezTerm and Neovim simultaneously (see below).

## Neovim

[Neovim](https://neovim.io/) config built on [LazyVim](https://www.lazyvim.org/) with a curated plugin set and a custom **TurboVim** menu bar that pays tribute to [Turbo Pascal 7](https://en.wikipedia.org/wiki/Turbo_Pascal).

Highlights:

- **TurboVim** — a local plugin that renders a Turbo Pascal 7-style menu bar (`<F10>` to toggle), with full keyboard navigation and dropdowns wired to LSP, Telescope, and DAP actions
- **LSP** via [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) + [Mason](https://github.com/mason-org/mason.nvim): C/C++ (clangd), C# (Roslyn), Helm, YAML — auto-installed on first launch
- **Debugging** via [nvim-dap](https://github.com/mfussenegger/nvim-dap): codelldb (C/C++), netcoredbg (C#), js-debug-adapter (JS/TS)
- **Fuzzy finding** with [Telescope](https://github.com/nvim-telescope/telescope.nvim) + fzf native sorter
- **File management** with [oil.nvim](https://github.com/stevearc/oil.nvim) (edit the filesystem like a buffer) and [neo-tree](https://github.com/nvim-neo-tree/neo-tree.nvim)
- **AI assist** via [codecompanion.nvim](https://github.com/olimorris/codecompanion.nvim) backed by the `pi` CLI
- **Syntax** via [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
- **Folding** via [nvim-ufo](https://github.com/kevinhwang91/nvim-ufo)

See [`nvim/README.md`](nvim/README.md) for the full plugin list, TurboVim keybindings, and setup instructions.

## Switching themes

```sh
bash scripts/switch-theme.sh
```

On first run it clones [tinted-theming/schemes](https://github.com/tinted-theming/schemes) (shallow, base16 only) into `~/.local/share/tinted-theming/schemes`. Subsequent runs do a fast-forward pull to keep the list current.

Pick a scheme with fzf — the YAML preview shows the palette and author. On confirmation it rewrites the `config.color_scheme` line in `~/.wezterm.lua`. WezTerm picks up the change on reload; Neovim picks it up on next start.

**Dependencies:** `git`, `fzf`

## The WezTerm / Neovim connection

**Neovim reads your WezTerm config at startup to pick its color scheme.** Set the theme once in `.wezterm.lua` and both the terminal and editor update together.

It works by parsing the `config.color_scheme` line in `~/.wezterm.lua`. As long as the scheme name ends in `(base16)` — like `"darkmoss (base16)"` — Neovim translates it to the matching `nvim-base16` name and applies it. If the file isn't there or the scheme doesn't match that pattern, it falls back to a classic Borland colorscheme.

To switch themes, just change this one line in `.wezterm.lua`:

```lua
config.color_scheme = "gruvbox-dark-hard (base16)"
```

Any [base16 scheme](https://github.com/tinted-theming/base16-schemes) works.

## Setup

You'll need Neovim ≥ 0.9, git, make, and a [Nerd Font](https://www.nerdfonts.com/).

```sh
# WezTerm
cp .wezterm.lua ~/.wezterm.lua

# Neovim
ln -sf "$(pwd)/nvim" ~/.config/nvim

# Open nvim — lazy.nvim installs everything on first launch
nvim
```

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
