## TurboVim

A built-in menu bar inspired by Turbo Pascal 7, implemented as a local plugin (`dev/turbovim/`).

```
████████╗██╗   ██╗██████╗ ██████╗  ██████╗ ██╗   ██╗██╗███╗   ███╗
╚══██╔══╝██║   ██║██╔══██╗██╔══██╗██╔═══██╗██║   ██║██║████╗ ████║
   ██║   ██║   ██║██████╔╝██████╔╝██║   ██║╚██╗ ██╔╝██║██╔████╔██║
   ██║   ██║   ██║██╔══██╗██╔══██╗██║   ██║ ╚████╔╝ ██║██║╚██╔╝██║
   ██║   ╚██████╔╝██║  ██║██████╔╝╚██████╔╝  ╚═══╝  ██║██║ ╚═╝ ██║
   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═════╝  ╚═════╝          ╚═╝╚═╝     ╚═╝
```

### Keybindings

| Key | Action |
|-----|--------|
| `<F10>` | Activate / deactivate the menu bar |
| `Alt+f/e/s/c/r/w/h` | Jump directly to File / Edit / Search / Code / Run / Window / Help |
| `←` / `→` | Navigate between menus (also switches dropdown when one is open) |
| `↓` / `Enter` | Open the dropdown for the selected menu |
| `↑` / `↓` | Navigate items within an open dropdown |
| `Enter` | Execute the selected item |
| `Esc` | Close dropdown (first press) or deactivate menu bar (second press) |

### Menus

| Menu | Contents |
|------|----------|
| **File** | Open file, Recent files, New buffer, Save, Save All, Close buffer, Quit |
| **Edit** | Undo, Redo, Find, Find & Replace |
| **Search** | Live grep, Find in buffer, Document symbols, Workspace symbols |
| **Code** | Code action, Rename, Format, Hover docs, Diagnostics, References, Go to definition |
| **Run** | Make, Terminal |
| **Window** | Split horiz/vert, Close, Close others, Move left/right/up/down |
| **Help** | Keymaps, Commands, Check health, Mason, About TurboVim |

Search and file operations use Telescope. Code operations use the active LSP server.

### Plugin structure

```
dev/turbovim/lua/turbovim/
  init.lua        setup entry point
  state.lua       shared state
  highlights.lua  TP7-style colors
  menus.lua       menu definitions
  bar.lua         tabline renderer
  dropdown.lua    floating window submenus
  keymaps.lua     navigation state machine
  splash.lua      ASCII art logo (Help → About TurboVim)
```

## Setup

```sh
./setup.sh
```

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
| turbovim *(local)* | Turbo Pascal 7-style menu bar — see [TurboVim](#turbovim) |
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
