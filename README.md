# dotfiles

A minimal set of dotfiles used for development: [Neovim](https://neovim.io/), zsh, Midnight Commander, and the [pi](https://pi.dev) coding agent, served via [Ollama](https://ollama.ai).

## Setup

```sh
make install
```

Requirements: Neovim ≥ 0.9, git, Terminess Nerd Font.

Open Neovim — lazy.nvim installs packages on first launch.


## Neovim

Built on LazyVim. LSP, debugging, fuzzy finding, file management, database UI, AI assist via CodeCompanion.nvim (switchable between Ollama and GitHub Copilot with `ga` in the chat buffer), text transforms, syntax highlighting, and folding.

## zsh

oh-my-zsh with lambda theme and git plugin. Sets `PATH`, sources per-host configs, aliases `vim` to `nvim`, and sets `$EDITOR` to Neovim.

## Midnight Commander

`make install-mc` symlinks config. Internal editor disabled, `F4` opens Neovim.

## pi agent

[pi](https://pi.dev) is a local-first AI coding agent that talks to Ollama. `make setup-host` points it at whatever model Ollama currently has loaded (falling back to the most recently pulled model if none is loaded). Start Ollama, load a model (`ollama run <model>`), then run `pi`.

## Contact

jacob.andresen@gmail.com
