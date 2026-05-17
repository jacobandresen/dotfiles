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
| [fidget.nvim](https://github.com/j-hui/fidget.nvim) | LSP progress notifications |
| [symbol-usage.nvim](https://github.com/Wansmer/symbol-usage.nvim) | Inline reference counts |

### Debugging (DAP)
| Plugin | Purpose |
|--------|---------|
| [nvim-dap](https://github.com/mfussenegger/nvim-dap) | Debug Adapter Protocol client |
| [nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui) | DAP UI |
| [nvim-dap-vscode-js](https://github.com/mxsdev/nvim-dap-vscode-js) | JavaScript/TypeScript debugging |
| [nvim-dap-cs](https://github.com/NicholasMata/nvim-dap-cs) | C# debugging |

### Editor
| Plugin | Purpose |
|--------|---------|
| [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) | Fuzzy finder |
| [telescope-fzf-native](https://github.com/nvim-telescope/telescope-fzf-native.nvim) | Native fzf sorter for Telescope |
| [oil.nvim](https://github.com/stevearc/oil.nvim) | File manager as a buffer |
| [neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim) | File tree |
| [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) | Syntax highlighting & parsing |
| [autoclose.nvim](https://github.com/m4xshen/autoclose.nvim) | Auto-close brackets/quotes |
| [wrapping.nvim](https://github.com/andrewferrier/wrapping.nvim) | Soft/hard wrap toggling |
| [nvim-tmux-navigation](https://github.com/alexghergh/nvim-tmux-navigation) | Seamless nvim/tmux pane navigation |
| [snacks.nvim](https://github.com/folke/snacks.nvim) | Collection of small QoL utilities |

### AI
| Plugin | Purpose |
|--------|---------|
| [codecompanion.nvim](https://github.com/olimorris/codecompanion.nvim) | AI chat & inline assist (via `pi` CLI) |

### UI
| Plugin | Purpose |
|--------|---------|
| [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) | Status line |
| [bamboo.nvim](https://github.com/ribru17/bamboo.nvim) | Default colorscheme |
| [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim) | Rendered Markdown in buffer |
| [ansify.nvim](https://github.com/tmccombs/ansify.nvim) | Colorize ANSI escape sequences |
| [nvim-ufo](https://github.com/kevinhwang91/nvim-ufo) | Better folding |
| [mini.icons](https://github.com/nvim-mini/mini.icons) | Icon provider |

## LSP Servers

Managed by Mason, auto-installed on startup:

- **clangd** — C/C++
- **roslyn** — C#
- **helm_ls** — Helm charts
- **yaml-language-server** — YAML

## DAP Adapters

Managed by Mason, auto-installed on startup:

- **codelldb** — C/C++
- **netcoredbg** — C#
- **js-debug-adapter** — JavaScript/TypeScript

## Dependencies

| Tool | Purpose |
|------|---------|
| `git` | Plugin manager bootstrap |
| `make`, `gcc` | Build telescope-fzf-native, compile Treesitter parsers |
| `node` / `npm` | Required by js-debug-adapter |
| `python3` | URL/HTML encode-decode transforms |
| `jq` | JSON formatting (`formatprg`) and transforms |
| `pi` | CLI backend for CodeCompanion AI |
| `wl-clipboard` | System clipboard support on Wayland (`wl-copy`/`wl-paste`) |
