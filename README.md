# dotfiles

A minimal set of dotfiles used for development: [Neovim](https://neovim.io/), Midnight Commander, and the [pi](https://pi.dev) coding agent, served via [Ollama](https://ollama.ai).

## Setup

```sh
make install
```

Requirements: Neovim ≥ 0.9, git, Terminess Nerd Font.

Open Neovim — lazy.nvim installs packages on first launch.


## Neovim

Built on LazyVim. LSP, debugging, fuzzy finding, file management, database UI, AI assist via CodeCompanion.nvim (switchable between Ollama and GitHub Copilot with `ga` in the chat buffer), text transforms, syntax highlighting, and folding.

## Midnight Commander

`make install-mc` symlinks config. Internal editor disabled, `F4` opens Neovim.

## pi agent

[pi](https://pi.dev) is a local-first AI coding agent that talks to Ollama. `make install-pi` detects the machine's RAM profile, pulls and warms up the best-fitting coding model (`qwen3-coder:30b` on ≥24GB machines, `qwen2.5-coder:14b` otherwise — see `scripts/select-coding-model.sh`), then runs `setup-host.sh` to point pi at it. Re-run `make setup-host` any time to repoint pi at whatever model Ollama currently has loaded instead.

## Ollama

`make install-ollama` detects total system RAM (`scripts/detect-ram-profile.sh`) and installs the matching systemd drop-in from `ollama/ollama.service.d/` to `/etc/systemd/system/ollama.service.d/override.conf`, then restarts the service. Both profiles enable iGPU/Vulkan acceleration, flash attention, and q8_0 KV cache quantization, and cap Ollama's memory with a systemd `MemoryHigh`; machines with ≥24GB RAM get the `32gb` profile (16k context, 1 loaded model, 10m keep-alive, 14G memory cap), everything else gets the more conservative `16gb` profile (8k context, 1 loaded model, 10m keep-alive, 7G memory cap).

## Docker

`make install-docker` (skipped if Docker isn't installed) detects the same RAM profile and installs a matching systemd drop-in from `docker/docker.service.d/` to `/etc/systemd/system/docker.service.d/override.conf`, then restarts the service. This keeps Docker from starving Ollama (or vice versa) on shared boxes: the `32gb` profile caps Docker at ~12G (`MemoryHigh=12G`, `MemoryMax=13G`), the `16gb` profile caps it at ~6G (`MemoryHigh=6G`, `MemoryMax=7G`).

## Contact

jacob.andresen@gmail.com
