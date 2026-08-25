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

## Ollama

`make install-ollama` detects total system RAM (`scripts/detect-ram-profile.sh`) and installs the matching systemd drop-in from `ollama/ollama.service.d/` to `/etc/systemd/system/ollama.service.d/override.conf`, then restarts the service. Both profiles enable iGPU/Vulkan acceleration, flash attention, and q8_0 KV cache quantization; machines with ≥24GB RAM get the `32gb` profile (32k context, 2 loaded models, 30m keep-alive), everything else gets the more conservative `16gb` profile (8k context, 1 loaded model, 10m keep-alive).

## Contact

jacob.andresen@gmail.com
