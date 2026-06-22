# dotfiles

My personal, Commodore 64-themed dotfiles: [Neovim](https://neovim.io/), [WezTerm](https://wezfurlong.org/wezterm/), zsh, Midnight Commander, and the [pi](https://pi.dev) coding agent.

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

`.wezterm.lua` themes the terminal as a Commodore 64 boot screen (commodore VIC-II
palette, light-blue-on-blue, blinking block cursor) using the **C64 Pro Mono**
font with Hack Nerd Font Mono as a glyph fallback. `make install-fonts` installs
both.

A matching **"C64" app icon** (committed under `icons/wezterm/`) can be installed
separately — it's intentionally *not* part of `make install`:

```sh
make install-icon
```

- **Linux** (Arch / Ubuntu): drops PNGs into `~/.local/share/icons/hicolor/` and
  refreshes the icon caches. Log out/in if the launcher doesn't update.
- **macOS**: rebuilds `WezTerm.app`'s `.icns` with `sips`/`iconutil` (backs up the
  original to `terminal.icns.orig`). Note this edits the signed app bundle, so it's
  reset on the next WezTerm update; restore with the backed-up file.

## zsh

`.zshrc` (oh-my-zsh, no theme) sets a Commodore 64 BASIC-style prompt — a bare
`READY.` on its own line — with a dim, right-aligned cwd and git branch via
`vcs_info`. It aliases `vim`→`nvim`, points `$EDITOR`/`$VISUAL` at Neovim, and
wraps `pi` with a default tool allowlist (`read,write,edit,bash`).

It also pins the local LLM for the [`mu`](https://github.com/jacobandresen/mu)
agent so it uses the **same model as pi** —
`MU_AGENT_MODEL=qwen2.5-coder-7b-instruct` (the **Q3_K_L** quant, chosen by a 10-problem
dojo board as the best model that runs on 8 GB — the 7B Q4_K_M won't load and 8B models hit
a GPU "Compute error") and `MU_NUM_CTX=6000` (keeps the KV cache off swap). The id must
match LM Studio's `/v1/models` (the bare name, since it's the only 7B variant; a second one
would get an `lmstudio-community/…` prefix). Without the pin, mu auto-selects the first
`/v1/models` entry, which can be a model too large to load.

## Midnight Commander

`mc/ini` is symlinked to `~/.config/mc/ini` by `make install-mc`. The internal
editor is disabled so `F4` opens Neovim (`$EDITOR`).

## pi agent

[pi](https://pi.dev) is a local-first AI coding agent. This setup uses [LM Studio](https://lmstudio.ai) as the backend with **Qwen2.5-Coder-7B-Instruct** at the **Q3_K_L** quant (~3.8 GB) — the strongest coding model that runs on this 8 GB M2. It was chosen by boarding six local models on a ten-problem coding suite (see [mu/docs/quantization-and-the-stack.md](https://github.com/jacobandresen/mu/blob/main/docs/quantization-and-the-stack.md)): the 7B solved the most (7/10), and at Q3_K_L it stays under the host's ~4.1 GB GPU compute-buffer ceiling. (The 3B remains a lighter fallback if you want snappier interactive latency over capability.)

`pi` (the standalone CLI agent), Neovim's CodeCompanion, and the `mu` dojo agent all talk to the same LM Studio server on `http://localhost:1234` using the same Qwen2.5-Coder-7B model; there is no proxy in between.

### Setup

```sh
make setup-lmstudio   # downloads Qwen2.5-Coder-7B (Q3_K_L), disables guardrails, wires pi config
```

On macOS, LM Studio is also installed via `make deps` (`brew install --cask lm-studio`). On Linux, download the AppImage from [lmstudio.ai](https://lmstudio.ai) and run `make setup-lmstudio` after.

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
