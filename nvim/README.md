# Neovim Config

My personal Neovim setup. Curated plugin list with a setup script for Arch, Ubuntu/Debian (including WSL), and macOS.

## Setup

Supports Arch Linux, Ubuntu/Debian (including WSL), and macOS (Homebrew).

## Plugins

### LSP & Completion
| Plugin | Purpose |
|--------|---------|
| [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) | LSP client configuration |
| [mason.nvim](https://github.com/mason-org/mason.nvim) | LSP/DAP/tool installer |
| [mason-tool-installer](https://github.com/WhoIsSethDaniel/mason-tool-installer.nvim) | Auto-install Mason tools |
| [roslyn.nvim](https://github.com/seblj/roslyn.nvim) | C# (Roslyn) LSP support |
| [rustaceanvim](https://github.com/mrcjkb/rustaceanvim) | Rust LSP, inlay hints, macro expansion, DAP |
| [fidget.nvim](https://github.com/j-hui/fidget.nvim) | LSP progress notifications |
| [symbol-usage.nvim](https://github.com/Wansmer/symbol-usage.nvim) | Inline reference counts |

### Debugging (DAP)
| Plugin | Purpose |
|--------|---------|
| [nvim-dap](https://github.com/mfussenegger/nvim-dap) | Debug Adapter Protocol client |
| [nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui) | DAP UI |
| [nvim-dap-vscode-js](https://github.com/mxsdev/nvim-dap-vscode-js) | JavaScript/TypeScript debugging |
| [nvim-dap-cs](https://github.com/NicholasMata/nvim-dap-cs) | C# debugging |
| [nvim-jdtls](https://github.com/mfussenegger/nvim-jdtls) | Java LSP + debugging (via LazyVim `lang.java` extra) |

### Editor
| Plugin | Purpose |
|--------|---------|
| [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) | Fuzzy finder |
| [telescope-fzf-native](https://github.com/nvim-telescope/telescope-fzf-native.nvim) | Native fzf sorter for Telescope |
| [oil.nvim](https://github.com/stevearc/oil.nvim) | File manager as a buffer (replaces neo-tree) |
| [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) | Syntax highlighting & parsing |
| [nvim-tmux-navigation](https://github.com/alexghergh/nvim-tmux-navigation) | Seamless nvim/tmux pane navigation |
| [snacks.nvim](https://github.com/folke/snacks.nvim) | Collection of small QoL utilities |

A local `transform.lua` spec adds a Telescope-driven **text transform picker**
(`<leader>mm`, normal or visual): JSON prettify/minify/escape/unescape (`jq`),
URL and HTML encode/decode (`python3`), and Base64 encode/decode.

### Database
| Plugin | Purpose |
|--------|---------|
| [vim-dadbod](https://github.com/tpope/vim-dadbod) | Database client |
| [vim-dadbod-ui](https://github.com/kristijanhusak/vim-dadbod-ui) | Database UI (`<leader>Du` toggle) |
| [vim-dadbod-completion](https://github.com/kristijanhusak/vim-dadbod-completion) | SQL completion source (via blink.cmp) |

### AI
| Plugin | Purpose |
|--------|---------|
| [gp.nvim](https://github.com/Robitx/gp.nvim) | AI chat & inline assist (via LM Studio, auto-detects local Mistral models) |

### Jupyter
| Plugin | Purpose |
|--------|---------|
| [molten-nvim](https://github.com/benlubas/molten-nvim) | Run code interactively against a Jupyter kernel, inline output |
| [jupytext.nvim](https://github.com/GCBallesteros/jupytext.nvim) | Open/save `.ipynb` as plain `py:percent` text |
| [image.nvim](https://github.com/3rd/image.nvim) | Inline plots/images (WezTerm kitty graphics, ImageMagick CLI) |

Run `make setup-jupyter` from the repo root **before first launching nvim** — it
builds the `~/.virtualenvs/neovim` Python host (pynvim + jupyter), registers a
`neovim` kernel, and installs the `jupytext` CLI, so molten's `:UpdateRemotePlugins`
build step can find pynvim. Keys live under `<leader>j` (`<leader>ji` init kernel,
`<leader>jl` run line, `<leader>jv` run selection, `<leader>jr` run operator,
`<leader>jo`/`<leader>jh` show/hide output, `<leader>jI` import `.ipynb` outputs).

Notebooks drop into **visual mode** automatically once a kernel is live for the
buffer — on opening a notebook whose kernel is already running, or right after
`<leader>ji` connects one (`User MoltenKernelReady`). With no kernel responding,
the buffer opens normally.

### UI
| Plugin | Purpose |
|--------|---------|
| [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) | Status line |
| [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim) | Rendered Markdown in buffer |
| [nvim-ufo](https://github.com/kevinhwang91/nvim-ufo) | Better folding |
| [mini.icons](https://github.com/nvim-mini/mini.icons) | Icon provider |

## LSP Servers

Managed by Mason, auto-installed on startup:

- **clangd** — C/C++
- **roslyn** — C#
- **rust-analyzer** — Rust (driven by rustaceanvim)
- **jdtls** — Java
- **helm_ls** — Helm charts
- **yaml-language-server** — YAML

## DAP Adapters

Managed by Mason, auto-installed on startup:

- **codelldb** — C/C++ and Rust
- **netcoredbg** — C#
- **js-debug-adapter** — JavaScript/TypeScript
- **java-debug-adapter** + **java-test** — Java (installed by the LazyVim `lang.java` extra)

## Dependencies

| Tool | Purpose |
|------|---------|
| `git` | Plugin manager bootstrap |
| `make`, `gcc` | Build telescope-fzf-native, compile Treesitter parsers |
| `node` / `npm` | Required by js-debug-adapter |
| `python3` | URL/HTML encode-decode transforms |
| `jupyter`, `jupytext` | Jupyter notebooks via molten-nvim (`make setup-jupyter`) |
| ImageMagick (`magick`) | Inline image rendering for molten (image.nvim) |
| `jq` | JSON formatting (`formatprg`) and transforms |
| `pi` | Standalone CLI coding agent (shares the LM Studio backend) |
| LM Studio | Local model server (`:1234`) for continue.nvim & `pi` |
| `wl-clipboard` | System clipboard support on Wayland (`wl-copy`/`wl-paste`) |
