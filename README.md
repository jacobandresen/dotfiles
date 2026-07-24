# dotfiles

A minimal set of dotfiles used for development: [Neovim](https://neovim.io/), [WezTerm](https://wezfurlong.org/wezterm/), zsh, Midnight Commander, and the [pi](https://pi.dev) coding agent — defaulting to **gemma4**, served via [Ollama](https://ollama.ai).

## Setup

```sh
make install
```

Requirements: Neovim ≥ 0.9, git, Terminess Nerd Font.

Open Neovim — lazy.nvim installs packages on first launch.


## Neovim

Built on LazyVim. LSP, debugging, fuzzy finding, file management, database UI, AI assist via gp.nvim, text transforms, syntax highlighting, and folding.

## WezTerm

Apple Classic color scheme, Hack Nerd Font Mono. `make install-fonts` installs the font. `make install-wezterm-icon` sets a custom icon (Linux only).

## zsh

oh-my-zsh with lambda theme and git plugin. Sets `PATH`, sources per-host configs, aliases `vim` to `nvim`, and sets `$EDITOR` to Neovim.

## Midnight Commander

`make install-mc` symlinks config. Internal editor disabled, `F4` opens Neovim.

## pi agent

[pi](https://pi.dev) is a local-first AI coding agent using **gemma4** via Ollama. `make setup-host` auto-configures the model. Start Ollama, then run `pi`.

## Contact

jacob.andresen@gmail.com
