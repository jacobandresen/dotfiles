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

A model must clear one bar before size is considered: **pi has to write a C
file, compile it and run it.** Three failure modes hide below that bar, and each
looks like success in the transcript:

| Model | What actually happens |
| --- | --- |
| `qwen2.5-coder:3b` / `:7b` | No tool call at all — a fenced JSON blob that looks like one. Nothing reaches disk, though `ollama show` advertises `tools`. |
| `llama3.2:3b` | Passes a one-tool probe in isolation, then reverts to text mimicry under pi's real prompt and full tool set. |
| `llama3.1:8b` | Calls tools for real and mangles the arguments — writes the literal characters `\n` into the source and drops `#include <stdio.h>`, so the C never compiles. |
| `qwen3:4b` | Writes valid C, compiles it, runs it. |

`make verify-model` (`scripts/verify-agent-model.sh`) is the check that catches
all three: it runs pi non-interactively in a temp directory, then compiles and
runs whatever landed on disk. It grades the artifact, not the transcript —
the only thing separating `llama3.1:8b`'s confident failure from a working model.

`scripts/select-coding-model.sh` then picks from the RAM profile *and*, on
macOS, the memory architecture:

| RAM | Linux (discrete GPU) | Apple silicon | Intel Mac |
| --- | --- | --- | --- |
| ≥24GB | `qwen3-coder:30b` | `qwen3-coder:30b` | `qwen3:4b` |
| 12–24GB | `qwen3:8b` | `qwen3:8b` | `qwen3:4b` |
| <12GB | `qwen3:4b` | `qwen3:4b` | `qwen3:4b` |

Mac tiers are one step more conservative at the same nominal RAM. Apple silicon
has *unified* memory — the GPU allocation comes out of the same pool as the OS,
and Ollama can wire down only ~75% of it (`sysctl iogpu.wired_limit_mb`). A
Linux box with a 16GB discrete GPU has that VRAM *on top of* system RAM; a 16GB
Mac does not. Intel Macs have no usable GPU path, so they take the smallest
passing tag at every size — also the least painful thing to run on a CPU.

Override with `DOTFILES_CODING_MODEL=<tag>`, honoured by the selector and
`scripts/setup-model.sh`. **Run `make verify-model` after any override** — a
model that cannot drive pi loads without complaint and then fails silently.

### Switching

`scripts/setup-host.sh` points pi at **this host's selected model**, not at
whatever happens to be resident: anything that loads a model (`bench-model.sh`
does) would otherwise silently repoint pi at it.

To deliberately run a different model, `use-model.sh` loads it and passes
`--use-loaded`, which also updates nvim's CodeCompanion adapter and the
[mu](https://github.com/jacobandresen/mu) agent — both follow whichever model
Ollama has loaded:

```sh
make use-model MODEL=qwen3:8b   # any tag
make use-model                  # back to this host's selection
make use-bonsai                 # the opt-in 27B (see below)
make setup-host                 # re-assert the selector's pick
```

### Tuning

`make install-ollama` applies the profile. Each pins one loaded model and
`OLLAMA_NUM_PARALLEL=1` — the default of 4 multiplies KV cache memory for
concurrency nothing here uses.

- **Linux** — systemd drop-in from `ollama/ollama.service.d/`. Enables
  iGPU/Vulkan acceleration and flash attention, caps memory with `MemoryHigh`
  (4G / 7G / 19500M — the 32gb tier has to fit qwen3-coder:30b's ~17.3G GPU
  buffer, and a 16G `MemoryMax` OOM-killed the service mid-load).
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

`verify-model` answers *can it drive pi*; `scripts/bench-model.sh` answers
*does it fit*. The column that matters is `PROCESSOR` — anything short of
`100% GPU` means the model spilled layers to CPU. Measured on the 8GB M2 this
was written for, at the 16K context this repo configures:

```
MODEL               GEN_TPS  PROMPT_TPS    SIZE   SWAP_DELTA  PROCESSOR
qwen3:4b               29.0       160.7   3.9GB          0M   100% GPU
llama3.1:8b            16.2        64.8   6.3GB       +816M   28%/72% CPU/GPU
qwen2.5-coder:7b       17.5       137.8   5.2GB      +1036M   12%/88% CPU/GPU
bonsai-27b              7.5        17.8   4.2GB       +919M   100% GPU
```

The 4b is better on every axis than the 8b — 1.8x generation, 2.5x prompt, a
second to load instead of seven, no swap — *and* it is the one that can actually
drive the agent. That is why the 8gb tier stops there.

`bench-model.sh` deliberately measures fit and nothing else. It once carried a
`TOOLS` column probing for native tool calls; it was removed for being wrong in
*both* directions — `llama3.1:8b` returned a clean tool call then failed to
produce compilable C, while `qwen3:4b` spent the probe's token budget reasoning
and came back `finish_reason=length, tool_calls=null`, declaring the shipping
model unusable. Use `make verify-model` for that question.

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

**Verdict:** keep it for a deliberate one-off hard question; `qwen3:4b` for
interactive work (the tier's verified pick), `qwen3.5:4b` for agent runs.

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
