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

[pi](https://pi.dev) is a local-first AI coding agent that talks to Ollama. `make install-pi` detects the machine's RAM profile, pulls and warms up the best-fitting coding model, then runs `setup-host.sh` to point pi at it.

`scripts/select-coding-model.sh` picks that model from the RAM profile *and*, on macOS, the memory architecture:

| RAM | Linux (discrete GPU) | Apple silicon | Intel Mac |
| --- | --- | --- | --- |
| ≥24GB | `qwen3-coder:30b` | `qwen3-coder:30b` | `qwen2.5-coder:7b` |
| 12–24GB | `qwen2.5-coder:14b` | `qwen2.5-coder:7b` | `qwen2.5-coder:3b` |
| <12GB | `qwen2.5-coder:3b` | `qwen2.5-coder:3b` | `qwen2.5-coder:3b` |

The Mac tiers are one step more conservative at the same nominal RAM because Apple silicon uses *unified* memory: the GPU allocation comes out of the same pool as the OS and everything else, and Ollama can only wire down ~75% of it (`sysctl iogpu.wired_limit_mb`). A Linux box with a 16GB discrete GPU has that VRAM *on top of* system RAM; a 16GB Mac does not, so `qwen2.5-coder:14b` (~9GB before the KV cache) leaves nothing for the rest of the machine. Intel Macs have no usable GPU path, so they're sized for latency rather than RAM.

Override per-run with `DOTFILES_CODING_MODEL=<tag>`, honoured by both the selector and `scripts/setup-model.sh` (which also takes the tag as an argument). Re-run `make setup-host` any time to repoint pi at whatever model Ollama currently has loaded instead.

## Ollama

`make install-ollama` detects total system RAM (`scripts/detect-ram-profile.sh` — `8gb` under 12GB, `16gb` under 24GB, `32gb` at or above) and applies the matching profile. Every profile pins one loaded model and `OLLAMA_NUM_PARALLEL=1`, since the default of 4 multiplies KV cache memory for concurrency nothing here uses.

**Linux** installs the systemd drop-in from `ollama/ollama.service.d/` to `/etc/systemd/system/ollama.service.d/override.conf` and restarts the service. These enable iGPU/Vulkan acceleration and flash attention, and cap memory with `MemoryHigh` (4G / 7G / 10G).

**macOS** has no systemd, so `scripts/install-ollama-macos.sh` applies `ollama/launchd/<profile>.env` instead: each key goes through `launchctl setenv` (which is what the Ollama.app menubar server inherits), the app is restarted to pick them up, and the same values are written to `~/.ollama/dotfiles.env` — sourced from `.zshrc` so a hand-started `ollama serve` gets them too. `launchctl setenv` doesn't survive a reboot; re-run `make install-ollama` after one. The macOS profiles turn on q8_0 KV cache quantization, which works on Metal but not on the Linux Vulkan iGPU path, roughly halving KV cache RAM.

On an 8GB machine the budget is genuinely tight — macOS itself holds 3–4GB — so that profile also drops the keep-alive to 5m to hand memory back sooner.

## Docker

`make install-docker` (skipped if Docker isn't installed) applies the same RAM profile to Docker so it doesn't starve Ollama, or vice versa.

**Linux** installs a systemd drop-in from `docker/docker.service.d/` to `/etc/systemd/system/docker.service.d/override.conf` and restarts the service: `32gb` caps Docker at ~12G, `16gb` at ~6G, `8gb` at ~2G.

**macOS** has no cgroups to cap. Docker Desktop instead runs a Linux VM whose memory is reserved from the host up front, so the equivalent knob is its settings store — `scripts/install-docker-macos.sh` merges `docker/desktop/<profile>.json` into `~/Library/Group Containers/group.com.docker/settings-store.json`, preserving every other setting and leaving a `.bak`. Docker Desktop is quit first (it rewrites that file from memory on exit) and restarted afterwards if it was running. The `8gb` profile asks for a 2GB VM, 4 CPUs, no autostart, and the resource saver, which leaves room for a ~3GB model alongside it.

Docker Desktop is deliberately **not** part of `make deps` on macOS, since that up-front VM reservation is a bad default on a small machine. Run `make deps-docker-macos` to install and size it.

`make ram-profile` prints what this host detects as and which config files that selects.

## Contact

jacob.andresen@gmail.com
