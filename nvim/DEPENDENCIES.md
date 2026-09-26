# Dependencies

External tools this config expects on `$PATH`. Anything not listed here is
installed automatically by `lazy.nvim` (plugins) or Mason (LSP servers, DAP
adapters, formatters).

## Core

- **Neovim** >= 0.12 (`vim.lsp.config`, `:lsp restart`)
- **git** — plugin management, gitsigns, telescope
- **ripgrep** (`rg`) — `Telescope live_grep` / `grep_string`
- **make** + a C compiler (`gcc`/`cc`) — builds `telescope-fzf-native.nvim`
- **A Nerd Font** — statusline/dashboard/explorer icons (e.g. `Terminess Nerd
  Font`, set in `lua/config/options.lua`)
- **A truecolor terminal** (`COLORTERM=truecolor`) — the Turbo Pascal EGA
  colours in Neovim and the `turbopascal` Midnight Commander skin
- **[lazydocker](https://github.com/jesseduffield/lazydocker)** — `<leader>gd`
  opens it for containers/images/compose stacks. Installed by `make deps`.

## AI (`lua/plugins/ai.lua`)

- **curl** — queries the local Ollama API
- **[Ollama](https://ollama.com)** running at `localhost:11434` with at least
  one model pulled — powers the `ollama` CodeCompanion adapter and Minuet's
  inline ghost-text suggestions (`<A-A>` to accept)
- **GitHub Copilot** subscription — run `:Copilot auth` once to authenticate;
  used by the `copilot` CodeCompanion adapter

## SDL game dev (`lua/plugins/lsp.lua`)

- **pkg-config** — used by `<leader>rr` to build and run the current SDL
  C/C++ file

## Debugging (`lua/plugins/dap.lua`)

- **node** — runs Mason's `js-debug-adapter` for JS/TS debugging

## Text transforms (`lua/util/transform.lua`, `<leader>ct`)

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

LSP servers configured under `nvim-lspconfig` (`clangd`, `helm-ls`,
`docker-language-server`, `roslyn-language-server` for C#) are installed by
LazyVim. The rest are listed in the `mason.nvim` spec: `rust-analyzer` (run by
rustaceanvim), `netcoredbg`, `codelldb`, `js-debug-adapter`, `prettier`,
`black`, `isort`, `clang-format`, `goimports`, `csharpier`, plus LazyVim's own
`stylua` and `shfmt`.

Other servers you install through `:Mason` start automatically, except
`rust_analyzer`, `omnisharp` and `csharp_ls`, which are disabled so they don't
duplicate rustaceanvim and Roslyn.

`docker-language-server` needs the `yaml.docker-compose` filetype to attach
to compose files (mapped in `lua/config/options.lua`).

## Optional

- **yaml-language-server** — backs `helm_ls`'s YAML validation
  (`lua/plugins/lsp.lua`); install manually if editing Helm charts
