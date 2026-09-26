# Dependencies

External tools this config expects on `$PATH`. Anything not listed here is
installed automatically by `lazy.nvim` (plugins) or
`mason-tool-installer` (LSP servers, DAP adapters, formatters).

## Core

- **Neovim** >= 0.10
- **git** — plugin management, gitsigns, telescope
- **ripgrep** (`rg`) — `Telescope live_grep` / `grep_string`
- **make** + a C compiler (`gcc`/`cc`) — builds `telescope-fzf-native.nvim`
- **A Nerd Font** — statusline/dashboard/explorer icons (e.g. `Terminess Nerd
  Font`, set in `lua/config/options.lua`)
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
`clangd`, `js-debug-adapter`, `rust-analyzer`, `helm-ls`, `docker-language-server`,
`prettier`, `black`, `isort`, `clang-format`, `goimports`, `csharpier`, plus
`stylua` and `shfmt` (installed manually/via `:Mason` if missing).

`docker-language-server` needs the `yaml.docker-compose` filetype to attach
to compose files (mapped in `lua/config/autocmds.lua`).

## Optional

- **yaml-language-server** — backs `helm_ls`'s YAML validation
  (`lua/plugins/lsp.lua`); install manually if editing Helm charts
