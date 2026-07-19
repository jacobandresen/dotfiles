# dotfiles

![Bonsai-27B](https://img.shields.io/badge/Powered%20by-Bonsai--27B-%237749ff?style=flat-square)

My personal dotfiles: [Neovim](https://neovim.io/), [WezTerm](https://wezfurlong.org/wezterm/), zsh, Midnight Commander, and the [pi](https://pi.dev) coding agent — defaulting to **Bonsai-27B** (a ternary quantization of Qwen3.6-27B), loaded through [LM Studio](https://lmstudio.ai) like any other GGUF, with Mistral AI models ([Mistral-7B](https://mistral.ai/news/mistral-7b/), [Codestral](https://mistral.ai/news/codestral/)) available as a fallback.

## Setup

Requirements: Neovim ≥ 0.9, git, [Terminess Nerd Font](https://www.nerdfonts.com/font-downloads) (TerminessTTF).

```sh
make install   # deps + nvim, zsh, Midnight Commander, and pi configs (symlinked)
```

Open Neovim — [lazy.nvim](https://github.com/folke/lazy.nvim) installs all vim packages on first launch.


## Neovim

Built on [LazyVim](https://www.lazyvim.org/).

- **LSP** via [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) + [Mason](https://github.com/mason-org/mason.nvim): C/C++ (clangd), C# (Roslyn), Rust (rust-analyzer), Java (jdtls), Helm, YAML
- **Debugging** via [nvim-dap](https://github.com/mfussenegger/nvim-dap): codelldb (C/C++, Rust), netcoredbg (C#), js-debug-adapter (JS/TS), java-debug (Java)
- **Fuzzy finding** with [Telescope](https://github.com/nvim-telescope/telescope.nvim) + fzf native sorter
- **File management** with [oil.nvim](https://github.com/stevearc/oil.nvim) (neo-tree disabled)
- **Database UI** via [vim-dadbod](https://github.com/tpope/vim-dadbod) + dadbod-ui
- **AI assist** via [gp.nvim](https://github.com/Robitx/gp.nvim) backed by LM Studio
- **Text transforms** (JSON/URL/HTML/Base64) via a Telescope picker (`<leader>mm`)
- **Syntax** via [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
- **Folding** via [nvim-ufo](https://github.com/kevinhwang91/nvim-ufo)

## WezTerm

`.wezterm.lua` uses the **Apple Classic** color scheme with the **Hack Nerd Font
Mono** font (Hack as fallback), a blinking block cursor, and tab bar + scrollbar
enabled. `make install-fonts` installs the font.

`make install-wezterm-icon` swaps WezTerm's app icon for a **classic compact Mac**
— a beige Macintosh with a black CRT running a green-phosphor `>_` shell prompt.
The source lives in `assets/happy-mac.svg`
(regenerate with `scripts/gen-happy-mac.py`); the target installs PNGs into the
per-user hicolor theme, which overrides the packaged icon without touching the
WezTerm install. Linux only — restart WezTerm to pick it up. To revert, delete
`~/.local/share/icons/hicolor/*/apps/org.wezfurlong.wezterm.png`.

## zsh

`.zshrc` uses oh-my-zsh with the `lambda` theme and the `git` plugin. It puts
`~/.local/bin` and `~/.lmstudio/bin` on `PATH`, sources two per-host files if
present (`~/.zshrc.dev` for dev settings, `~/.zshrc.mu` for LLM tuning), aliases
`vim`→`nvim`, and points `$EDITOR`/`$VISUAL`/`$VIEWER` at Neovim (the last for
Midnight Commander's `F3`).

`~/.zshrc.mu` carries per-host LLM tuning for the [`mu`](https://github.com/jacobandresen/mu)
agent (`MU_AGENT_MODEL`, `MU_NUM_CTX`). It's machine-local and written by mu's own
`make setup-host` (see the [mu repo](https://github.com/jacobandresen/mu)); `.zshrc`
just sources it if present. mu and pi share one LM Studio model, so mu pins the
**same model pi's `setup-host` selects** — both apply the same GPU thresholds (the 7B
on a capable card, the snappier 3B otherwise).

That id must match LM Studio's `/v1/models`. LM Studio serves the 7B under the bare
name `qwen2.5-coder-7b-instruct` only while it's the sole 7B variant on the box;
adding a second 7B (e.g. a `qwen/…` A/B candidate) makes it namespace both as
`<publisher>/…` and the bare id disappears. Keep just one 7B installed — delete
extra variants from LM Studio (or `~/.lmstudio/models`) — so pi and mu keep resolving.

## Midnight Commander

`mc/ini` is symlinked to `~/.config/mc/ini` by `make install-mc`. The internal
editor is disabled so `F4` opens Neovim (`$EDITOR`).

## pi agent

[pi](https://pi.dev) is a local-first AI coding agent. **Default model: Bonsai-27B**
— a ternary/1-bit quantization of Qwen3.6-27B, a 27B-parameter model
squeezed to a 3.6–3.9 GB footprint that runs fully on a 6 GB card. It loads
through [LM Studio](https://lmstudio.ai) at `localhost:1234` like any other
GGUF — no separate server, no separate port. Mistral AI models (Mistral-7B,
Codestral-22B) remain available as a fallback/alternative under the same
`lmstudio` provider — see below.

`pi` (the standalone CLI agent), Neovim's gp.nvim, and the `mu` dojo agent all
talk to the same LM Studio server on `http://localhost:1234`; there is no
proxy in between.

### Setup

```sh
lms server start
curl -L -o /tmp/Bonsai-27B-Q1_0.gguf \
  https://huggingface.co/prism-ml/Bonsai-27B-gguf/resolve/main/Bonsai-27B-Q1_0.gguf
lms import -y -l /tmp/Bonsai-27B-Q1_0.gguf   # not hub-searchable, so a direct
                                              # download + import (skips the
                                              # useless hub-search step)
pi                                                       # uses Bonsai by default
                                                          # (pi/agent/models.json
                                                          # + settings.json.template)
```

`Bonsai-27B-Q1_0.gguf` isn't listed in LM Studio's own model search, so it
needs the manual download + `lms import` above (the `mu` repo automates this
exact step for its own `mu model load bonsai-27b` — see its
`client.py::_download_and_import_gguf` if you want the same for `pi`). LM
Studio serves the import back under a model id it derives from the GGUF's own
metadata, not the filename — currently `bonsai-27b` (check with
`lms ls --llm --json`'s `modelKey` field if this ever changes on a re-import,
and update `pi/agent/models.json` + `settings.json.template` to match). See
the [mu repo](https://github.com/jacobandresen/mu)'s `docs/MODELS.md` §
Bonsai-27B for the full model story and `docs/tech-repair.md` for the
ctx/parallel/spec-decode tuning this config is based on.

#### GPU offload: CUDA works, Vulkan doesn't

Bonsai-27B's `Q1_0` ternary quant only has correct dequantization kernels in
llama.cpp's **CPU** and **CUDA** backends. The **Vulkan** backend (used for
Intel/AMD iGPUs, including Serenity's Arc iGPU) loads the GGUF and runs
without error, but its `Q1_0` dequant kernel is wrong/unimplemented — it
silently produces garbage tokens (e.g. stray punctuation, no coherent text)
instead of failing loudly.

This is why offloading to the GPU works fine on an nvidia box (CUDA has real
`Q1_0` kernels) but breaks on the machine without nvidia (Vulkan iGPU). The fix is to pin
LM Studio's GGUF runtime to the **CPU-only `llama.cpp-…-avx2` engine** and
load with `--gpu 0`, never `--gpu max`, whenever Bonsai is the active model:

```sh
lms runtime select llama.cpp-linux-x86_64-avx2 --latest   # CPU engine, not vulkan
lms load --gpu 0 -c 32768 bonsai-27b                       # no GPU offload
```

`scripts/setup-lmstudio.sh` does the runtime-engine selection automatically
for the `bonsai-27b` model on Linux, and `scripts/setup-host.sh`'s
Serenity profile hard-codes `--gpu 0` in `LMSTUDIO_LOAD_ARGS` for this reason
— see the comments next to both for details. If Bonsai ever produces garbage
output again, check `lms runtime ls` for the `✓` next to an `avx2` (not
`vulkan`) engine first.

#### CPU-only performance: not recommended on ultra-low-VRAM hosts

Because Bonsai-27B must run on the CPU-only `avx2` engine (previous section),
a 27-billion-parameter model is fully CPU-bound on hosts with no usable dGPU
— like Serenity (Intel Core Ultra 5 135U, no dGPU, Intel Arc iGPU unusable
per above). Measured on Serenity (2026-07-19, 12 CPU threads, ctx 32768,
`pi -p "What is 2+2?"`):

| Metric | Measured |
| --- | --- |
| Prompt eval | ~2.8 tok/s |
| Generation | ~2.4 tok/s |
| pi's ~1900-token tool-call system prompt, cold | 5+ min, stuck at "Prompt processing progress: 0.0%" |
| Trivial round-trip, warm model | ~3.5 min |
| Trivial round-trip, cold + retries | ~13.5 min |

The 5+ minute prompt-processing stall is long enough to trip pi's default
5-minute HTTP idle timeout (`stopReason: "error"`, `errorMessage: "terminated"`,
silently retried) — see `pi/agent/settings.json`'s `httpIdleTimeoutMs: 0`,
which disables that timeout so slow-but-eventually-successful requests aren't
killed mid-flight. Disabling the timeout fixes the errors but not the
underlying slowness.

**Recommendation:** don't use Bonsai-27B (or any ~20B+ model) on hosts with no
usable GPU offload. `scripts/setup-host.sh` no longer defaults Serenity to
Bonsai-27B for this reason — it falls through to the same VRAM-based profile
picker used for GPUless/low-VRAM hosts generally, landing on the lightweight
`qwen2.5-coder-3b-instruct` fallback, which is small enough to run at
usable speed on CPU alone. Bonsai remains available and is left alone by
`setup-host.sh` if you set it manually (see § Setup above and the
`setup-host.sh` "EXCEPTION" comment), but expect the numbers above.

### LM Studio + Mistral AI (fallback / alternative)

The previous default, kept available under the same `lmstudio` provider
(`pi --model mistralai/mistral-7b-instruct-v0.3`). Model selection is
**automatic and hardware-optimized** via `make setup-host`:

- **≥16 GB VRAM** → Codestral-22B with Q4_K_M (~14 GB)
- **11-16 GB VRAM** → Codestral-22B with Q3_K_L (~11 GB)
- **6-11 GB VRAM** → Mistral-7B-Instruct with Q4_K_M (~4.4 GB)
- **4-6 GB VRAM** → Mistral-7B-Instruct with Q3_K_L (~3.8 GB)
- **<4 GB VRAM** → Qwen2.5-Coder-3B with Q3_K_L (~3.8 GB, fallback)

| Model | Size | VRAM (Q4_K_M) | Default For | Notes |
|-------|------|--------------|-------------|-------|
| Codestral-22B | 22B | ~14 GB | 16+ GB VRAM | Opt-in flagship coding model |
| Codestral-Latest | 22B | ~14 GB | 16+ GB VRAM | Latest Codestral version |
| Mistral-7B-Instruct v0.2 | 7B | ~4.4 GB | 6-11 GB VRAM | LM Studio-path default |
| Mistral-7B-Instruct v0.1 | 7B | ~4.4 GB | 6-11 GB VRAM | Previous version |
| Mixtral-8x7B | 47B | ~24 GB | 24+ GB VRAM | High-capability MoE |
| Qwen2.5-Coder-7B | 7B | ~4.4 GB | Fallback | Compatibility |
| Qwen2.5-Coder-3B | 3B | ~3.8 GB | <4 GB VRAM | Minimal VRAM |

```sh
make setup-host       # auto-detect GPU, install Mistral-7B or Codestral
make setup-lmstudio   # or just the model: downloads Mistral/Codestral, wires pi config
```

`make setup-host` probes the GPU once, downloads the appropriate Mistral AI
model via LM Studio, and writes `defaultModel` into `~/.pi/agent/settings.json`.
**It leaves the Bonsai default alone**: if `defaultModel` is already a
Bonsai-27B id, it skips the pi-settings patch entirely rather than overwriting
it with a Mistral/Codestral pick (Bonsai and Mistral both run under the same
`lmstudio` provider now, so there's no `defaultProvider` to key off of) —
switching back to this path from Bonsai is a manual edit of
`~/.pi/agent/settings.json`, not something running this script will do for you.

mu shares the same LM Studio server when using this path but tunes itself:
its own `make setup-host` writes `MU_AGENT_MODEL` / `MU_NUM_CTX` to
`~/.zshrc.mu` (machine-local, sourced by `.zshrc`), applying the same GPU
thresholds so mu and pi resolve to the same Mistral AI model.

The tracked `.zshrc` stays identical across machines. pi's `defaultModel` is
*host-managed* — because `~/.pi` symlinks into the repo, the live
`pi/agent/settings.json` is gitignored and seeded from
`pi/agent/settings.json.template` by `make install-pi`, so each machine sets
its own model without churning the repo.

On macOS, LM Studio is also installed via `make deps` (`brew install --cask lm-studio`). On Linux, download the AppImage from [lmstudio.ai](https://lmstudio.ai) and run `make setup-host` after.

Start LM Studio (load the model), then run `pi` (uses whatever `defaultModel`
`make setup-host` set) or `pi --model mistralai/mistral-7b-instruct-v0.3` to
pick Mistral explicitly over an already-set Bonsai default. `make
setup-lmstudio` also patches the GGUF chat template (`scripts/patch-gguf-template.py`)
so tool calls parse cleanly.

### Neovim integration

The `gp.nvim` plugin (`nvim/lua/plugins/ai.lua`) connects to LM Studio's
OpenAI-compatible API at `http://localhost:1234/v1`, pinned to
`bonsai-27b`. It warns (doesn't block) if LM Studio isn't
reachable when you send a message. To use Mistral instead, edit the
`openai_model_id` field in that file to your loaded Mistral model id.

**Keys:**
- `<leader>ac` — Toggle chat
- `<leader>an` — New chat  
- `<leader>ap` — Paste selection to chat
- `<leader>ai` — Replace selection with AI
- `<leader>ae` — Explain selected code
- `<leader>ar` — Rewrite selected code

## Contact

You can reach me at jacob.andresen@gmail.com .
