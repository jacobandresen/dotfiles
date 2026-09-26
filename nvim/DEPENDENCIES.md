# Dependencies

External tools this config expects on `$PATH`. Anything not listed here is
installed automatically by `lazy.nvim` (plugins) or
`mason-tool-installer` (LSP servers, DAP adapters, formatters).

## Core

- **Neovim** >= 0.10
- **git** — plugin management, gitsigns, telescope
- **ripgrep** (`rg`) — `Telescope live_grep` / `grep_string`
- **make** + a C compiler (`gcc`/`cc`) — builds `telescope-fzf-native.nvim`
- **A Nerd Font** — statusline/dashboard/oil icons (e.g. `Terminess Nerd Font`,
  set in `lua/config/options.lua`)

## AI (`lua/plugins/ai.lua`)

- **curl** — queries the local Ollama API
- **[Ollama](https://ollama.com)** running at `localhost:11434` with at least
  one model pulled, for the `ollama` CodeCompanion adapter and for Minuet's
  inline ghost-text suggestions (`milanglacier/minuet-ai.nvim`, `<A-A>` to
  accept, auto-triggered while typing in code filetypes)
- **GitHub Copilot** subscription — run `:Copilot auth` once to authenticate;
  used by the `copilot` CodeCompanion adapter

## SDL game dev (`lua/plugins/lsp.lua`)

- **pkg-config** — `<leader>rr` (in a `c`/`cpp` buffer) detects the SDL
  major version and any companion libs (`*_image`, `*_ttf`, `*_mixer`) from
  the current file's `#include`s, then compiles and runs it via `cc`/`c++`
  and `pkg-config --cflags/--libs`. Meant for quick single-file experiments;
  real projects should use their own build system instead.
- clangd is given a fallback `-I` flag for SDL2's classic `#include <SDL.h>`
  style (SDL3's `#include <SDL3/SDL.h>` already resolves without one) - only
  applies to files with no `compile_commands.json`.

## Text transforms (`lua/plugins/transform.lua`)

- **jq** — JSON prettify/minify/escape/unescape
- **python3** — URL/HTML encode/decode
- **base64** (coreutils) — base64 encode/decode

## Language toolchains

Not managed by Mason; install via the language's own tooling:

- **Rust**: `cargo`/`rustc` (rustup), `rustfmt` — used by rustaceanvim and
  the `rust` formatter
- **Go**: `go` toolchain — provides `gofmt`
- **.NET SDK**: `dotnet` — required for C# projects (Roslyn/nvim-dap-cs debug
  and build)

## Mason-managed (auto-installed, see `lua/plugins/lsp.lua`)

LSP servers, DAP adapters, and formatters: `roslyn`, `netcoredbg`, `codelldb`,
`clangd`, `js-debug-adapter`, `rust-analyzer`, `helm-ls`, `prettier`, `black`,
`isort`, `clang-format`, `goimports`, `csharpier`, plus `stylua` and `shfmt`
(installed manually/via `:Mason` if missing).

## Optional

- **yaml-language-server** — backs `helm_ls`'s YAML validation
  (`lua/plugins/lsp.lua`); install manually if editing Helm charts
