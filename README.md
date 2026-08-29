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

The model has to clear one bar before size is even considered: **pi must be able to write a C file, compile it and run it.** That is a much higher bar than it sounds, and three separate failure modes hide below it — each one looks like success in the transcript:

| Model | What actually happens |
| --- | --- |
| `qwen2.5-coder:3b` / `:7b` | Emits no tool call at all. Prints a fenced JSON blob that looks like one; nothing reaches disk. `ollama show` advertises `tools` for both. |
| `llama3.2:3b` | Passes a one-tool probe in isolation, then reverts to text mimicry under pi's real system prompt and full tool set. |
| `llama3.1:8b` | Calls the tools for real — and mangles the arguments. Writes the two literal characters `\n` into the source and drops `#include <stdio.h>`, so the C never compiles. This was the previous pick, chosen precisely because it got further than anything else. |
| `qwen3:4b` | Writes valid C, compiles it, runs it. |

`scripts/verify-agent-model.sh` (`make verify-model`) is the check that catches all three: it runs pi non-interactively in a temp directory, then compiles and runs whatever landed on disk. It grades the artifact, not the transcript — which is the only thing that separates `llama3.1:8b`'s confident failure from a working model.

```
MODEL                  WROTE    COMPILES   RUNS      VERDICT
----------------------------------------------------------------------
qwen2.5-coder:7b       no       no         no        FAIL
llama3.1:8b            yes      no         no        FAIL
qwen3:4b               yes      yes        yes       PASS
```

`scripts/select-coding-model.sh` then picks from the RAM profile *and*, on macOS, the memory architecture:

| RAM | Linux (discrete GPU) | Apple silicon | Intel Mac |
| --- | --- | --- | --- |
| ≥24GB | `qwen3-coder:30b` | `qwen3-coder:30b` | `qwen3:4b` |
| 12–24GB | `qwen3:8b` | `qwen3:8b` | `qwen3:4b` |
| <12GB | `qwen3:4b` | `qwen3:4b` | `qwen3:4b` |

The Mac tiers are one step more conservative at the same nominal RAM because Apple silicon uses *unified* memory: the GPU allocation comes out of the same pool as the OS and everything else, and Ollama can only wire down ~75% of it (`sysctl iogpu.wired_limit_mb`). A Linux box with a 16GB discrete GPU has that VRAM *on top of* system RAM; a 16GB Mac does not. Intel Macs have no usable GPU path, so they take the smallest passing tag at every size — it is also the least painful thing to run on a CPU.

Override per-run with `DOTFILES_CODING_MODEL=<tag>`, honoured by both the selector and `scripts/setup-model.sh` (which also takes the tag as an argument). Run `make verify-model` after any override; a model that cannot drive pi will load without complaint and then fail silently.

`scripts/bench-model.sh` checks the *fit* side of the prediction on real hardware. With no argument it benchmarks this host's selection, or pass tags to compare them. The column that matters is `PROCESSOR` — anything short of `100% GPU` means the model didn't fit the wirable budget and Ollama spilled layers to CPU. Measured on the 8GB M2 this was written for:

```
MODEL                   GEN_TPS PROMPT_TPS   LOAD_S     SIZE SWAP_DELTA  PROCESSOR
qwen3:4b                   29.0    160.7     0.82    3.9GB         0M  100% GPU
llama3.1:8b                16.2     64.8     7.36    6.3GB       816M  28%/72% CPU/GPU
```

Both at the 16K context this repo now configures. The 4b is 1.8x the generation rate and 2.5x the prompt rate, loads in a second instead of seven, and leaves swap alone — while the 8b spills 28% of its layers to CPU and pulls in 816MB of swap. The smaller model is better on every axis here *and* it is the one that can actually drive the agent.

`bench-model.sh` deliberately measures fit and nothing else. It used to carry a `TOOLS` column that probed for native tool calls; that column was removed because it was wrong in *both* directions — `llama3.1:8b` returned a clean tool call and then failed to produce compilable C, while `qwen3:4b` spent the probe's token budget reasoning and came back `finish_reason=length, tool_calls=null`, i.e. the probe declared the shipping model unusable. Use `make verify-model` for that question.

Re-run `make setup-host` any time to repoint pi at whatever model Ollama currently has loaded instead.

## Ollama

`make install-ollama` detects total system RAM (`scripts/detect-ram-profile.sh` — `8gb` under 12GB, `16gb` under 24GB, `32gb` at or above) and applies the matching profile. Every profile pins one loaded model and `OLLAMA_NUM_PARALLEL=1`, since the default of 4 multiplies KV cache memory for concurrency nothing here uses.

**Linux** installs the systemd drop-in from `ollama/ollama.service.d/` to `/etc/systemd/system/ollama.service.d/override.conf` and restarts the service. These enable iGPU/Vulkan acceleration and flash attention, and cap memory with `MemoryHigh` (4G / 7G / 10G).

**macOS** has no systemd, and it has two Ollama servers that read their configuration from two different places:

- **`ollama serve` started from a shell** reads the environment, like the Linux service. `scripts/install-ollama-macos.sh` covers it by writing `~/.ollama/dotfiles.env` (sourced from `.zshrc`) and calling `launchctl setenv` for each key in `ollama/launchd/<profile>.env`.
- **The Ollama.app menubar server does not read the environment at all.** It constructs the environment for its child `ollama serve` from its own settings store and overwrites whatever launchd exported.

That second point silently defeated this repo's macOS tuning for as long as it existed. Setting every key to a deliberately non-default value with `launchctl setenv` and then reading the child server's real environment back (Ollama 0.33.2):

| `launchctl setenv` said | the running server got |
| --- | --- |
| `OLLAMA_KEEP_ALIVE=7m` | `OLLAMA_KEEP_ALIVE=5m` |
| `OLLAMA_KV_CACHE_TYPE=q4_0` | `OLLAMA_KV_CACHE_TYPE=q8_0` |
| `OLLAMA_NUM_PARALLEL=2` | `OLLAMA_NUM_PARALLEL=1` |
| `OLLAMA_MAX_LOADED_MODELS=3` | `OLLAMA_MAX_LOADED_MODELS=1` |
| `OLLAMA_FLASH_ATTENTION=0` | `OLLAMA_FLASH_ATTENTION=1` |

Nothing got through. The profile only *looked* like it worked because every value in it happens to equal the app's own default — including the q8_0 KV cache quantization the profiles were written to enable, which the app turns on by itself.

Context length is the exception, and the one that matters most: it lives in the app's SQLite settings store (`~/Library/Application Support/Ollama/db.sqlite`, `settings.context_length`, where `0` means "use the 8192 default"). The installer writes it there — quitting the app first, since it rewrites that database from memory on exit — and keeps a `.bak`. Verify with `ollama ps`; the `CONTEXT` column should read 16384.

Keep-alive, KV cache type and parallelism have no equivalent knob in the app's store, so under the menubar app they stay at the app's defaults. That is survivable today only because those defaults match the profiles; a profile wanting 10m or 30m keep-alive would not get it. Use a shell-started `ollama serve` if you need those honoured. `launchctl setenv` also doesn't survive a reboot; re-run `make install-ollama` after one.

The macOS profiles also run a 16K context where Linux stays at 8K. That is the same q8_0 trade: halved KV cache RAM pays for the larger window, and the window matters because pi's system prompt and tool schemas are ~1.7K tokens before any work starts — one compile-fix-recompile loop with the compiler output pasted back in walks straight through an 8K window, and truncating mid-loop is how the agent "forgets" the file it just wrote. Vulkan has no KV quantization, so the Linux drop-ins stay at 8192 until there is real VRAM to spend.

On an 8GB machine the budget is genuinely tight — macOS itself holds 3–4GB — so that profile also drops the keep-alive to 5m to hand memory back sooner. It fits the 16K window because the selected model shrank: at 16K `qwen3:4b` is 3.9GB resident and stays 100% on GPU, where the previous pick was 6.3GB and spilled 28% to CPU.

## Docker

`make install-docker` (skipped if Docker isn't installed) applies the same RAM profile to Docker so it doesn't starve Ollama, or vice versa.

**Linux** installs a systemd drop-in from `docker/docker.service.d/` to `/etc/systemd/system/docker.service.d/override.conf` and restarts the service: `32gb` caps Docker at ~12G, `16gb` at ~6G, `8gb` at ~2G.

**macOS** has no cgroups to cap. Docker Desktop instead runs a Linux VM whose memory is reserved from the host up front, so the equivalent knob is its settings store — `scripts/install-docker-macos.sh` merges `docker/desktop/<profile>.json` into `~/Library/Group Containers/group.com.docker/settings-store.json`, preserving every other setting and leaving a `.bak`. Docker Desktop is quit first (it rewrites that file from memory on exit) and restarted afterwards if it was running. The `8gb` profile asks for a 2GB VM, 4 CPUs, no autostart, and the resource saver, which leaves room for a ~3GB model alongside it.

Docker Desktop is deliberately **not** part of `make deps` on macOS, since that up-front VM reservation is a bad default on a small machine. Run `make deps-docker-macos` to install and size it.

`make ram-profile` prints what this host detects as and which config files that selects.

## Contact

jacob.andresen@gmail.com
