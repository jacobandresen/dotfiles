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

## Midnight Commander

`mc/ini` is symlinked to `~/.config/mc/ini` by `make install-mc`. The internal
editor is disabled so `F4` opens Neovim (`$EDITOR`).

## pi agent

[pi](https://pi.dev) is a local-first AI coding agent. This setup uses [LM Studio](https://lmstudio.ai) as the backend with **Qwen2.5-Coder-3B-Instruct** (~2.1 GB, Q4_K_M) — a coding-specialised model that fits comfortably in 8 GB unified memory and stays responsive alongside the terminal/editor.

Both `pi` (the standalone CLI agent) and Neovim's CodeCompanion talk to the same LM Studio server on `http://localhost:1234`; there is no proxy in between.

### Setup

```sh
make setup-lmstudio   # downloads Qwen2.5-Coder-3B, disables guardrails, wires pi config
```

On macOS, LM Studio is also installed via `make deps` (`brew install --cask lm-studio`). On Linux, download the AppImage from [lmstudio.ai](https://lmstudio.ai) and run `make setup-lmstudio` after.

Start LM Studio (load the model), then run `pi`. The config enables skill
commands and bundles the `@ollama/pi-web-search` package for web search. `make
setup-lmstudio` also patches the GGUF chat template (`scripts/patch-gguf-template.py`)
so tool calls parse cleanly.

### Neovim integration

The `codecompanion.nvim` plugin connects directly to LM Studio and auto-detects the loaded model via `/v1/models`. Keys: `<leader>ac` (chat toggle), `<leader>aa` (actions), `<leader>ai` (inline assist).

## Contact

You can reach me at jacob.andresen@gmail.com .
