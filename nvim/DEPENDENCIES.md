# Dependencies

External tools this config expects on `$PATH`. Anything not listed here is
installed automatically by `lazy.nvim` (plugins) or Mason (LSP servers, DAP
adapters, formatters).

## Core

- **Neovim** >= 0.12 (`vim.lsp.config`, `:lsp restart`)
- **git** — plugin management, gitsigns
- **ripgrep** (`rg`) — live grep / grep word
- **BigBlueTermPlus Nerd Font Mono** — installed by `make install-fonts` for
  Neovide and the configured kitty terminal; includes Nerd Font tool icons
- **A truecolor terminal** (`COLORTERM=truecolor`) — required by the configured
  Neovim colours
- **[lazydocker](https://github.com/jesseduffield/lazydocker)** — `<leader>gd`
  opens it for containers/images/compose stacks. Installed by `make deps`.

## AI (`lua/plugins/ai.lua`, `lua/util/agents.lua`)

- **pi-agent** with Ollama `qwen3.5-coding:4b` (derived from Qwen 3.5 4B Q4) — `<leader>ap` toggles the terminal;
  `<leader>as` sends the file or selection. Its Markdown output uses the
  Retrobox palette in `themes/pi-retrobox.json`. Buffers reload on focus.

Plugin updates are explicit (`:Lazy update`); startup does not update plugins.
The generated `lazy-lock.json` is local and ignored by git.
`<leader>ff` respects ignore rules; `<leader>fI` includes ignored files.
`<leader>cF` applies a server-provided `source.fixAll` action. ESLint and
Biome LSP servers start only in projects with their respective config files.

## Debugging (`lua/plugins/dap.lua`)

- **node** — runs Mason's `js-debug-adapter` for JS/TS debugging

## Text transforms (`lua/util/transform.lua`, `<leader>ct`)

- **jq** — JSON prettify/minify/escape/unescape
- **python3** — URL/HTML encode/decode
- **base64** (coreutils) — base64 encode/decode

Transforms support character selections, whole-line selections and whole
buffers. Rectangular selections are rejected. The picker keeps the original
buffer and selection, and cancels if that buffer changes while it is open.
URL encode/decode preserves whitespace.

Check with `NVIM_LOG_FILE=/tmp/nvim-transforms.log nvim --headless -u NONE -i NONE -l nvim/tests/transforms.lua`.

## Databases (Dadbod, `<leader>D`)

Install the client for the databases you use: **sqlite3** for SQLite, **psql**
for PostgreSQL, or **mysql** for MySQL/MariaDB. Dadbod uses these executables;
Mason does not install them.

`Space D u` opens the drawer. Press `A` there to add a connection, and `R`
after editing connections. Use `:DBUIFindBuffer` to assign an existing SQL
buffer to a connection and locate it in the drawer.

`Space D e` executes the whole query buffer, or selected lines in Visual mode.
DBUI queries support `:parameters` and record the last query
(`:DBUILastQueryInfo`). Dadbod UI's buffer-local `Space E` edits bind
parameters and `Space W` saves a scratch query. Saving SQL does **not**
execute it.

Connections and saved queries live under `stdpath("data")/db_ui`, outside this
repository. Standalone SQL can
also use Dadbod's `b:db`, `g:db`, `w:db`, `t:db` or `DATABASE_URL` connection.

Run `python3 nvim/tests/dadbod.py` from the repository root to check the real
Neovim configuration and installed plugins against temporary SQLite databases.
The runner isolates connection files, cache and state, and disables unrelated
Mason/parser installation for the test session.
Add `--postgres` to repeat the workflows against a temporary PostgreSQL cluster
when `initdb`, `pg_ctl` and `psql` are installed. It listens on a private Unix
socket and is stopped and removed afterward.

## Language toolchains

Not managed by Mason; install via the language's own tooling:

- **Rust**: `cargo`/`rustc` (rustup), `rustfmt` — used by rustaceanvim and
  the `rust` formatter
- **Go**: `go` toolchain — provides `gofmt` and supports `gopls`
- **.NET SDK**: `dotnet` — required for C# projects (Roslyn/nvim-dap-cs debug
  and build)

## Mason-managed (auto-installed, see `lua/plugins/lsp.lua`)

LSP servers configured under `nvim-lspconfig` (`clangd`, `gopls`, `eslint`,
`biome`, `helm-ls` and `docker-language-server`) are installed by LazyVim.
Roslyn is installed by Mason when `roslyn-language-server` is not already executable; an existing
executable from an older Mason `roslyn` package is reused to avoid the duplicate
shim conflict. The rest are listed in the `mason.nvim` spec: `rust-analyzer`
(run by rustaceanvim), `netcoredbg`, `codelldb`, `js-debug-adapter`, `prettier`,
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

## Performance defaults

- Roslyn compiler/analyzer diagnostics cover open files; reference code lenses are off.
- Rust uses default Cargo features and `cargo check`; `<leader>rc` runs Clippy
  in a terminal. Configure additional Cargo features per project when needed.
- LazyVim provides folding. Log/JSONL buffers reload on focus or buffer entry.

Use `:Lazy profile` to inspect actual plugin load times and loading triggers.
