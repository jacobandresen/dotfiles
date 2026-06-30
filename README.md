# dotfiles

[![Mistral AI](https://img.shields.io/badge/Powered%20by-Mistral%20AI-%237749ff?style=flat-square)](https://mistral.ai/)

My personal dotfiles: [Neovim](https://neovim.io/), [WezTerm](https://wezfurlong.org/wezterm/), zsh, Midnight Commander, and the [pi](https://pi.dev) coding agent with **Mistral AI focus** — defaulting to [Mistral-7B](https://mistral.ai/news/mistral-7b/) for broad compatibility, with [Codestral](https://mistral.ai/news/codestral/) available for high-VRAM setups.

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
- **AI assist** via [codecompanion.nvim](https://github.com/olimorris/codecompanion.nvim) backed by LM Studio
- **Jupyter notebooks** via [molten-nvim](https://github.com/benlubas/molten-nvim) + [jupytext.nvim](https://github.com/GCBallesteros/jupytext.nvim) + [image.nvim](https://github.com/3rd/image.nvim) (`make setup-jupyter`)
- **Text transforms** (JSON/URL/HTML/Base64) via a Telescope picker (`<leader>mm`)
- **Syntax** via [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
- **Folding** via [nvim-ufo](https://github.com/kevinhwang91/nvim-ufo)

See [`nvim/README.md`](nvim/README.md) for the full plugin list, keybindings, and setup notes.

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

[pi](https://pi.dev) is a local-first AI coding agent. This setup uses [LM Studio](https://lmstudio.ai) as the backend with a **Mistral AI focus**. The default model is **Mistral-7B-Instruct v0.2** — a versatile, efficient coding model that runs well on most GPUs including the 6 GB GTX 1660 SUPER. For more capable hardware (11+ GB VRAM), **Codestral-22B** is available as an opt-in choice.

All model selection is **automatic and hardware-optimized** via `make setup-host`:

- **≥16 GB VRAM** → Codestral-22B with Q4_K_M (~14 GB)
- **11-16 GB VRAM** → Codestral-22B with Q3_K_L (~11 GB)
- **6-11 GB VRAM** → Mistral-7B-Instruct with Q4_K_M (**default for most cards**, ~4.4 GB)
- **4-6 GB VRAM** → Mistral-7B-Instruct with Q3_K_L (~3.8 GB)
- **<4 GB VRAM** → Qwen2.5-Coder-3B with Q3_K_L (~3.8 GB, fallback)

`pi` (the standalone CLI agent), Neovim's CodeCompanion, and the `mu` dojo agent all talk to the same LM Studio server on `http://localhost:1234` using the configured Mistral AI model; there is no proxy in between.

### Supported Models

| Model | Size | VRAM (Q4_K_M) | Default For | Notes |
|-------|------|--------------|-------------|-------|
| Codestral-22B | 22B | ~14 GB | 16+ GB VRAM | Opt-in flagship coding model |
| Codestral-Latest | 22B | ~14 GB | 16+ GB VRAM | Latest Codestral version |
| **Mistral-7B-Instruct v0.2** | **7B** | **~4.4 GB** | **6-11 GB VRAM** | **Default for most GPUs** |
| Mistral-7B-Instruct v0.1 | 7B | ~4.4 GB | 6-11 GB VRAM | Previous version |
| Mixtral-8x7B | 47B | ~24 GB | 24+ GB VRAM | High-capability MoE |
| Qwen2.5-Coder-7B | 7B | ~4.4 GB | Fallback | Compatibility |
| Qwen2.5-Coder-3B | 3B | ~3.8 GB | <4 GB VRAM | Minimal VRAM |

### Setup

```sh
make setup-host       # auto-detect GPU, install Mistral-7B or Codestral
make setup-lmstudio   # or just the model: downloads Mistral/Codestral, wires pi config
```

`make setup-host` probes the GPU once and applies a hardware profile:

- **LM Studio** — downloads the appropriate Mistral AI model with the right quant.
- **pi** — sets `defaultModel` in `~/.pi/agent/settings.json` to Mistral-7B on typical hardware, or Codestral-22B on high-VRAM cards (≥11 GB). This is global for all pi consumers.

mu shares the same LM Studio server but tunes itself: its own `make setup-host` writes `MU_AGENT_MODEL` / `MU_NUM_CTX` to `~/.zshrc.mu` (machine-local, sourced by `.zshrc`), applying the same GPU thresholds so mu and pi resolve to the same Mistral AI model. See the [mu repo](https://github.com/jacobandresen/mu).

The tracked `.zshrc` stays identical across machines. pi's `defaultModel` is *host-managed* — because `~/.pi` symlinks into the repo, the live `pi/agent/settings.json` is gitignored and seeded from `pi/agent/settings.json.template` by `make install-pi`, so each machine sets its own model (Mistral-7B for most, Codestral-22B for 11+ GB VRAM) without churning the repo. Re-run after a hardware change. `make setup-lmstudio` is the model-only subset (downloads Mistral-7B by default, applies quant logic, no pi tuning).

**On this machine (GTX 1660 SUPER, 6 GB VRAM):** Runs Mistral-7B-Instruct v0.2 with Q4_K_M quant.

On macOS, LM Studio is also installed via `make deps` (`brew install --cask lm-studio`). On Linux, download the AppImage from [lmstudio.ai](https://lmstudio.ai) and run `make setup-host` after.

Start LM Studio (load the model), then run `pi`. The config enables skill
commands and bundles the `@ollama/pi-web-search` package for web search. `make
setup-lmstudio` also patches the GGUF chat template (`scripts/patch-gguf-template.py`)
so tool calls parse cleanly.

### Neovim integration

The `codecompanion.nvim` plugin connects directly to LM Studio and auto-detects the loaded model via `/v1/models`. Keys: `<leader>ac` (chat toggle), `<leader>aa` (actions), `<leader>ai` (inline assist).

## Jupyter

Notebooks run inside Neovim via [molten-nvim](https://github.com/benlubas/molten-nvim)
(interactive kernel execution with inline output), [jupytext.nvim](https://github.com/GCBallesteros/jupytext.nvim)
(edit `.ipynb` as plain `py:percent` text), and [image.nvim](https://github.com/3rd/image.nvim)
(inline plots through WezTerm's kitty graphics protocol + the ImageMagick CLI).

```sh
make setup-jupyter   # build the nvim Python host venv, register a kernel, install jupytext
```

This is standalone (not part of `make install`). It creates a dedicated venv at
`~/.virtualenvs/neovim` with `--system-site-packages` (inheriting the distro's
Jupyter/SciPy stack), registers a `neovim` kernel, installs the `jupytext` CLI via
`pipx`, and symlinks `jupyter/jupytext.toml` → `~/.jupyter/jupytext.toml`. Neovim's
`options.lua` auto-detects the venv as its `python3_host_prog`. **Run it before the
first `nvim` launch** so molten's `:UpdateRemotePlugins` build can find `pynvim`.
If any `:Molten*` command errors on first use, run `:UpdateRemotePlugins` once and
restart Neovim (regenerates the remote-plugin manifest).

Open a notebook (`.ipynb`, transparently shown as `py:percent` cells) or any `.py`
with `# %%` markers, then `<leader>ji` to start a kernel and `<leader>jl` to run a
line. JupyterLab is untouched — run `jupyter lab` as before.

## Contact

You can reach me at jacob.andresen@gmail.com .
