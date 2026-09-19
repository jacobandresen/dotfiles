# dotfiles

Development setup for [Neovim](https://neovim.io/), Midnight Commander, and the
[pi](https://pi.dev) coding agent, served by local models via
[Ollama](https://ollama.ai). Everything is sized to the machine's RAM.

```sh
make install
```

Requirements: Neovim ≥ 0.9, git, Terminess Nerd Font. Open Neovim once —
lazy.nvim installs plugins on first launch.

## Make targets

| Target | What it does |
| --- | --- |
| `make install` | deps + all configs below |
| `make install-nvim` / `install-mc` / `install-pi` | symlink that config |
| `make install-ollama` | apply the RAM-matched Ollama profile |
| `make install-docker` | apply the same RAM profile to Docker |
| `make install-bonsai` | build the opt-in Bonsai 27B model |
| `make use-model MODEL=<tag>` | point pi, nvim and mu at `<tag>` |
| `make use-bonsai` | same, for Bonsai |
| `make setup-host` | re-point pi at whatever Ollama has loaded |
| `make ram-profile` | print this host's profile and what it selects |

## Editors

**Neovim** — LazyVim, with LSP, debugging, fuzzy finding, file management,
database UI, text transforms and folding. AI assist via CodeCompanion.nvim,
switchable between Ollama and GitHub Copilot with `ga` in the chat buffer.
External tools it expects: [nvim/DEPENDENCIES.md](nvim/DEPENDENCIES.md).

**Midnight Commander** — internal editor disabled, `F4` opens Neovim.

## Local models

One RAM profile drives everything. `scripts/detect-ram-profile.sh` reports
`8gb` (under 12GB), `16gb` (under 24GB) or `32gb`, and that picks the coding
model, the Ollama tuning and the Docker limits.

### Which model

`scripts/select-coding-model.sh` keys off the profile *and*, on macOS, the
memory architecture:

| RAM | Linux (discrete GPU) | Apple silicon | Intel Mac |
| --- | --- | --- | --- |
| ≥24GB | `qwen3-coder:30b` | `qwen3-coder:30b` | `qwen2.5-coder:7b` |
| 12–24GB | `qwen2.5-coder:14b` | `qwen2.5-coder:7b` | `qwen2.5-coder:3b` |
| <12GB | `qwen2.5-coder:3b` | `qwen2.5-coder:3b` | `qwen2.5-coder:3b` |

Mac tiers are one step more conservative at the same nominal RAM. Apple silicon
has *unified* memory — the GPU allocation comes out of the same pool as the OS,
and Ollama can wire down only ~75% of it (`sysctl iogpu.wired_limit_mb`). A
Linux box with a 16GB discrete GPU has that VRAM *on top of* system RAM; a 16GB
Mac does not. Intel Macs have no usable GPU path, so they're sized for latency.

Override with `DOTFILES_CODING_MODEL=<tag>`, honoured by the selector and
`scripts/setup-model.sh`.

### Switching

pi, nvim's CodeCompanion adapter and the [mu](https://github.com/jacobandresen/mu)
agent all resolve *whichever model Ollama currently has loaded*, so one command
moves the whole stack:

```sh
make use-model MODEL=qwen3.5:4b   # any tag
make use-model                    # back to this host's selection
make use-bonsai                   # the opt-in 27B (see below)
```

### Tuning

`make install-ollama` applies the profile. Each pins one loaded model and
`OLLAMA_NUM_PARALLEL=1` — the default of 4 multiplies KV cache memory for
concurrency nothing here uses.

- **Linux** — systemd drop-in from `ollama/ollama.service.d/`. Enables
  iGPU/Vulkan acceleration and flash attention, caps memory with `MemoryHigh`
  (4G / 7G / 10G).
- **macOS** — no systemd, so `scripts/install-ollama-macos.sh` applies
  `ollama/launchd/<profile>.env` via `launchctl setenv` (what the menubar app
  inherits), restarts the app, and writes `~/.ollama/dotfiles.env` for
  shell-launched `ollama serve`. Turns on q8_0 KV cache quantization, which
  works on Metal but not the Linux Vulkan path, roughly halving KV cache RAM.

`launchctl setenv` doesn't survive a reboot — re-run after one. On 8GB the
budget is tight (macOS holds 3–4GB), so that profile drops keep-alive to 5m.

> **`OLLAMA_CONTEXT_LENGTH` is server-wide and overrides a model's own
> `num_ctx`.** A stale `~/.ollama/dotfiles.env` serving 16384 cost **2.1x
> throughput** on Bonsai (3.5 → 7.5 tok/s) at identical memory. It is sourced
> from `.zshrc`, so only *interactive* shells see it.

### Benchmarks

The tiers are a prediction; `scripts/bench-model.sh` checks it. The column that
matters is `PROCESSOR` — anything short of `100% GPU` means the model didn't fit
the wirable budget and Ollama spilled layers to CPU. Measured on the 8GB M2 this
was written for:

```
MODEL               GEN_TPS  PROMPT_TPS    SIZE   SWAP_DELTA  PROCESSOR
qwen2.5-coder:3b       38.5       295.1   2.3GB          0M   100% GPU
qwen2.5-coder:7b       17.5       137.8   5.2GB      +1036M   12%/88% CPU/GPU
bonsai-27b              7.5        17.8   4.2GB       +919M   100% GPU
```

The 7b is 2.2x slower and takes the machine into swap — which is why the `8gb`
tier stops at 3b. (`GEN_TPS` varies with machine load; these are idle-machine
runs and the best case for each.)

## Bonsai 27B — measured verdict

`make install-bonsai` builds [PrismML's Bonsai 27B](https://huggingface.co/prism-ml/Bonsai-27B-gguf)
— a 1-bit (Q1_0) compression of Qwen3.6-27B, Apache 2.0, 3.8GB. It is the only
way a 27B-class model runs at all on an 8GB Mac, and it keeps tool calling and
thinking. Not in `make install`, not what `select-coding-model.sh` picks.

**It works, and it is not worth it as a daily driver here.** Over 34 dojo
sessions on mu's 13-problem suite, against `qwen3.5:4b` on the same suite:

| | Bonsai 27B | qwen3.5:4b |
| --- | --- | --- |
| Solve rate | 38% (13/34) | ~49% |
| Trivial problems | helloworld 1/3, sqlite 1/4, sdl2 0/2 | 100% each |
| Mid-tier | gin, rust, vue-todo all 100% | 60% / 56% / 50% |
| Session time | 18.2 min | ~3x faster |

The average hides the real finding: **it is erratic in the wrong direction.** It
beats qwen on several mid-tier problems and solves flask and node-todo, which
qwen never does — but it fails *hello world* two times in three. Handling Rust
but not "hello world" is quantization damage, not a capability ceiling, and it
makes a poor agent driver: harnesses like mu distil *failure classes* into
fixes, and random failures on trivial problems are noise, not signal.

Throughput is also worse than the benchmark implies — 7.5 tok/s on short
prompts, ~1.5 tok/s on the ~5k-token prompts real agent turns use, where
prefill dominates.

**Verdict:** keep it for a deliberate one-off hard question; `qwen2.5-coder:3b`
for interactive work, `qwen3.5:4b` for agent runs.

Three things the setup must get right for it to work at all:

- **Vision projector dropped by default** — `ollama pull` also fetches a 629MB
  projector that Ollama loads into VRAM even when no image is sent, spilling 19
  of 65 layers to CPU (**1.0 tok/s**). Rebuilding without it restores all 65
  layers and ~7x throughput. `--with-vision` keeps it.
- **Context sized to the RAM profile**, not the model's 262144 ceiling: on 8GB
  `8192` → 65/65 layers, `16384` → 64/65, `32768` → 55/65 and 0.8 tok/s.
- **Thinking off for agent use** — `MU_REASONING_EFFORT=none` took a mu planner
  turn from 1107 tokens/359s to 295/105s (3.4x) with *more* usable content.
  See `~/.zshrc.mu`.

## Docker

`make install-docker` (skipped if Docker isn't installed) applies the same RAM
profile so Docker and Ollama don't starve each other.

- **Linux** — systemd drop-in from `docker/docker.service.d/`: `32gb` caps
  Docker at ~12G, `16gb` at ~6G, `8gb` at ~2G.
- **macOS** — no cgroups to cap; Docker Desktop reserves a VM up front, so
  `scripts/install-docker-macos.sh` merges `docker/desktop/<profile>.json` into
  its settings store, preserving other settings and leaving a `.bak`. Desktop is
  quit first (it rewrites that file on exit) and restarted after. The `8gb`
  profile asks for a 2GB VM, 4 CPUs, no autostart and the resource saver.

Docker Desktop is deliberately **not** in `make deps` on macOS — that up-front VM
reservation is a bad default on a small machine. Use `make deps-docker-macos`.

## Contact

jacob.andresen@gmail.com
