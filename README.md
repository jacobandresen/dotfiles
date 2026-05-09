# dotfiles

WezTerm and Neovim configs, wired together so they stay in sync.

```
.wezterm.lua    — terminal
nvim/           — editor (LazyVim-based)
```

## The WezTerm / Neovim connection

The only non-obvious thing here: **Neovim reads your WezTerm config at startup to pick its color scheme.** Set the theme once in `.wezterm.lua` and both the terminal and editor update together.

It works by parsing the `config.color_scheme` line in `~/.wezterm.lua`. As long as the scheme name ends in `(base16)` — like `"darkmoss (base16)"` — Neovim translates it to the matching `nvim-base16` name and applies it. If the file isn't there or the scheme doesn't match that pattern, it falls back to a classic Borland colorscheme.

To switch themes, just change this one line in `.wezterm.lua`:

```lua
config.color_scheme = "gruvbox-dark-hard (base16)"
```

Any [base16 scheme](https://github.com/chriskempson/base16) works.

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
| File explorer | `<leader>e` (oil.nvim) |
| Find files | `<leader>ff` |
| Live grep | `<leader>fs` |
| Open buffers | `<leader>fb` |
| Open all folds | `zR` |
| Close all folds | `zM` |
