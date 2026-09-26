# dotfiles

Neovim, Midnight Commander, kitty and zsh with an MS-DOS / Turbo Pascal look,
plus the [pi](https://pi.dev) coding agent on local [Ollama](https://ollama.ai)
models. Everything is sized to the machine's RAM.

```sh
make install
```

Requirements: Neovim ≥ 0.9, git, Terminess Nerd Font, More Perfect DOS VGA
(kitty). lazy.nvim installs plugins on first launch.

## Make targets

| Target | What it does |
| --- | --- |
| `make install` | deps + all configs below |
| `make install-nvim` / `-zsh` / `-mc` / `-kitty` / `-pi` | symlink that config |
| `make install-ollama` | apply the RAM-matched Ollama profile |
| `make install-docker` | apply the same RAM profile to Docker |
| `make use-model MODEL=<tag>` | point pi, nvim and mu at `<tag>` |
| `make setup-host` | re-point pi at this host's selected model |
| `make verify-model` | check the model can actually drive pi |
| `make ram-profile` | print this host's profile and what it selects |

## Look

- **Neovim** — LazyVim with a TP7 colorscheme, menu bar, hint line and window
  frames. LSP, debugging, database UI (Dadbod), text transforms. AI via
  CodeCompanion.nvim, Ollama or Copilot (`ga` in the chat buffer). External
  tools: [nvim/DEPENDENCIES.md](nvim/DEPENDENCIES.md).
- **Midnight Commander** — Turbo Pascal skin; `F4` opens Neovim.
- **kitty / zsh** — VGA font, EGA palette, 80x25, DOS-style prompt.

## Local models

`scripts/detect-ram-profile.sh` reports `8gb` (<12GB), `16gb` (<24GB) or
`32gb`; that picks the model, the Ollama tuning and the Docker limits.

| RAM | Linux (discrete GPU) | macOS |
| --- | --- | --- |
| ≥24GB | `qwen3-coder:30b` | `qwen3:4b` |
| 12–24GB | `qwen3:8b` | `qwen3:4b` |
| <12GB | `qwen3:4b` | `qwen3:4b` |

Macs don't tier: unified memory means the GPU budget comes out of system RAM
(Ollama can wire only ~75% of it), and `qwen3:4b` is the largest tag that stays
100% on GPU on an 8GB M2.

**A model must write, compile and run a C file through pi.** `qwen2.5-coder`
and `llama3.2:3b` fake tool calls as text; `llama3.1:8b` calls tools but
mangles the C. `make verify-model` grades what lands on disk, not the
transcript — run it after any override (`DOTFILES_CODING_MODEL=<tag>`).
`scripts/bench-model.sh` measures fit only; anything short of `100% GPU` in
its `PROCESSOR` column has spilled to CPU.

```sh
make use-model MODEL=qwen3:8b   # load another tag, repoint pi/nvim/mu
make use-model                  # back to this host's selection
```

### Tuning

`make install-ollama` pins one loaded model and `OLLAMA_NUM_PARALLEL=1`.

- **Linux** — systemd drop-in (`ollama/ollama.service.d/`): Vulkan, flash
  attention, `MemoryHigh` 4G / 7G / 19500M.
- **macOS** — `launchctl setenv` from `ollama/launchd/<profile>.env` plus
  `~/.ollama/dotfiles.env` for shell-launched `ollama serve`; q8_0 KV cache.
  Re-run after a reboot.

> `OLLAMA_CONTEXT_LENGTH` is server-wide and overrides a model's `num_ctx`. A
> stale value in `~/.ollama/dotfiles.env` once cost 2.1x throughput.

## Docker

`make install-docker` caps Docker to the same profile so it doesn't starve
Ollama: systemd drop-in on Linux (~2G / 6G / 12G), Docker Desktop settings
merge on macOS (`docker/desktop/<profile>.json`, backup left as `.bak`).
Docker Desktop isn't in `make deps` on macOS — use `make deps-docker-macos`.

## Contact

jacob.andresen@gmail.com
