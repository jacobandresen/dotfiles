# Dotfiles

Turbo Pascal-inspired configs for Neovim, Midnight Commander, kitty, zsh and
the [pi](https://pi.dev) coding agent with local
[Ollama](https://ollama.com) models.

## Install

```sh
make install
```

The installer detects the host OS and RAM profile, installs dependencies,
symlinks the configs, and applies matching Ollama and Docker limits. On macOS,
Docker Desktop is opt-in:

```sh
make deps-docker-macos
```

Requires Git, Neovim 0.12+, and a Nerd Font. Neovim plugins install on first
launch. See [nvim/DEPENDENCIES.md](nvim/DEPENDENCIES.md) for Neovim tools.

## Included

- **Neovim** — LazyVim with a Turbo Vision UI, LSP, debugging, database tools
  and AI integrations. Use `:colorscheme turbopascal` for the blue TP7 palette.
- **Midnight Commander** — matching retrobox and Turbo Pascal skins; F4 opens
  Neovim.
- **kitty and zsh** — VGA styling, a 120×40 layout and DOS-style prompt.
- **pi** — configured to use the host's selected Ollama model.

## Model controls

```sh
make ram-profile                  # show the detected profile and model
make use-model MODEL=<tag>       # switch pi, Neovim and mu
make use-model                    # restore the host-selected model
make verify-model                 # build and run a generated C program
make install-ollama install-docker
```

The last command reapplies the host's resource profile after a hardware or
configuration change.
