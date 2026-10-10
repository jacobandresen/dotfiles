# Dependencies

External tools this config expects on `$PATH`. Anything not listed here is
installed automatically by `lazy.nvim` (plugins) or Mason (LSP servers, DAP
adapters, formatters).

## Core

- **Neovim** >= 0.12 (`vim.lsp.config`, `:lsp restart`)
- **git** — plugin management, gitsigns
- **ripgrep** (`rg`) — live grep / grep word
- **A Nerd Font** — statusline/dashboard/explorer icons (e.g. `Terminess Nerd
  Font`, set in `lua/config/options.lua`)
- **A truecolor terminal** (`COLORTERM=truecolor`) — the retrobox / Turbo
  Pascal colours in Neovim and the matching Midnight Commander skins
- **[lazydocker](https://github.com/jesseduffield/lazydocker)** — `<leader>gd`
  opens it for containers/images/compose stacks. Installed by `make deps`.
- **docker** — the Docker explorer (`<leader>gC`, Tools ► Docker ► Explorer:
  containers by compose project/service, images, volumes, networks; `?` in
  it lists the keys) and Docker logs (`<leader>gO`). The **docker compose**
  plugin (`make deps-compose`, per user) is needed for up/down, services
  without a container yet and service logs; the rest only needs the CLI.

## AI (`lua/plugins/ai.lua`, `lua/util/agents.lua`)

- **pi-agent** with Ollama `ministral-3:3b` — `<leader>ap` toggles the terminal;
  `<leader>as` sends the file or selection. Buffers reload on focus.

Plugin updates are explicit (`:Lazy update`); startup does not update plugins.
`<leader>ff` respects ignore rules; `<leader>fI` includes ignored files.
`<leader>cF` requests server-provided `source.fixAll` actions, applying a single
action or prompting for alternatives. Servers without this action report no
available fixes.

## SDL game dev (`lua/plugins/lsp.lua`)

- **pkg-config** — used by `<leader>rr` to build and run the current SDL
  C/C++ file

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

`Space D u` opens the drawer; `Space D a` adds a connection. Press `R` in the
drawer after adding or editing connections. `Space D f` assigns an existing
SQL buffer to a connection and locates it in the drawer.

`Space D e` executes the whole query buffer, or selected lines in Visual mode.
DBUI queries support `:parameters` and record the last query (`Space D i`).
`Space D b` edits parameter values; `Space D s` saves a scratch query in its
connection's saved queries. Saving SQL does **not** execute it. These replace
Dadbod UI's default SQL shortcuts `Space S`, `Space E` and `Space W`.

Connections and saved queries live under `stdpath("data")/db_ui`, outside this
repository. `Space D c` edits the saved connections JSON. Standalone SQL can
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
- **Go**: `go` toolchain — provides `gofmt`
- **.NET SDK**: `dotnet` — required for C# projects (Roslyn/nvim-dap-cs debug
  and build)

## Mason-managed (auto-installed, see `lua/plugins/lsp.lua`)

LSP servers configured under `nvim-lspconfig` (`clangd`, `helm-ls` and
`docker-language-server`) are installed by LazyVim. Roslyn is installed by
Mason when `roslyn-language-server` is not already executable; an existing
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

- Reference counts are off until toggled for the current buffer with `<leader>uR`.
- Roslyn compiler/analyzer diagnostics cover open files; reference code lenses are off.
- Rust uses default Cargo features and `cargo check`; `<leader>rc` runs Clippy
  in a terminal. Configure additional Cargo features per project when needed.
- Folding loads when opening a buffer, rather than on an empty startup.
- Docker data loads asynchronously. Containers refresh every two seconds,
  CPU/memory every four seconds, and image/volume disk usage every thirty seconds.
  `R` forces a refresh in the Docker explorer.
- One shared timer refreshes visible log/JSONL buffers; hidden logs refresh
  when displayed again.

Use `:Lazy profile` to inspect actual plugin load times and loading triggers.
