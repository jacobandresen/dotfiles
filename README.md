# dotfiles

My personal, opinionated hackbox setup — not a minimal starter kit, but a reflection of my own preferences. [WezTerm](https://wezfurlong.org/wezterm/) and [Neovim](https://neovim.io/) configs, wired together so they share a single color scheme.


```
.wezterm.lua    — terminal
nvim/           — editor (LazyVim-based)
scripts/        — theme switcher + pi standalone launcher
pi/agent/       — pi coding agent config (settings, models, skills)
```

## Setup

You'll need Neovim ≥ 0.9, git, and [Terminess Nerd Font](https://www.nerdfonts.com/font-downloads) (TerminessTTF).

Clone the repo somewhere and symlink the configs into place:

```sh
git clone https://github.com/jacobandresen/dotfiles ~/dotfiles
cd ~/dotfiles

ln -sf "$(pwd)/.wezterm.lua" ~/.wezterm.lua
ln -sf "$(pwd)/nvim" ~/.config/nvim
ln -sf "$(pwd)/pi/agent" ~/.pi/agent
```

Then open Neovim — [lazy.nvim](https://github.com/folke/lazy.nvim) installs everything on first launch.

## WezTerm

[WezTerm](https://wezfurlong.org/wezterm/) is a GPU-accelerated terminal written in Rust. The config leans into a deliberately minimal, retro CMD.EXE look:

- **120×40 initial window** — a bit more breathing room than the classic 80×25

- **Blinking block cursor** at 530ms
- **Tab bar and scroll bar enabled**
- **4px padding** all around for a tight, edge-to-edge feel
- **[Atelier Forest Light (base16)](https://github.com/tinted-theming/base16-schemes)** as the default color scheme

## Neovim

Built on [LazyVim](https://www.lazyvim.org/) with a curated plugin set and a custom **TurboVim** menu bar that pays tribute to [Turbo Pascal 7](https://en.wikipedia.org/wiki/Turbo_Pascal).

- **TurboVim** — a local plugin that draws a TP7-style menu bar (`<F10>` to toggle), with keyboard navigation and dropdowns wired to LSP, Telescope, and DAP actions
- **LSP** via [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) + [Mason](https://github.com/mason-org/mason.nvim): C/C++ (clangd), C# (Roslyn), Helm, YAML — auto-installed on first launch
- **Debugging** via [nvim-dap](https://github.com/mfussenegger/nvim-dap): codelldb (C/C++), netcoredbg (C#), js-debug-adapter (JS/TS)
- **Fuzzy finding** with [Telescope](https://github.com/nvim-telescope/telescope.nvim) + fzf native sorter
- **File management** with [oil.nvim](https://github.com/stevearc/oil.nvim) and [neo-tree](https://github.com/nvim-neo-tree/neo-tree.nvim)
- **AI assist** via [codecompanion.nvim](https://github.com/olimorris/codecompanion.nvim) backed by the `pi` CLI
- **Syntax** via [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
- **Folding** via [nvim-ufo](https://github.com/kevinhwang91/nvim-ufo)

See [`nvim/README.md`](nvim/README.md) for the full plugin list, TurboVim keybindings, and setup notes.

## pi agent

[pi](https://github.com/badlogic/pi) is a local-first AI coding assistant backed by [Ollama](https://ollama.com/). It runs entirely on-device — no cloud API keys required.

The config lives in `pi/agent/` and is symlinked to `~/.pi/agent/` on setup. The following are **not** tracked:

- `auth.json` — OAuth tokens written by `pi login`; never committed
- `sessions/` — conversation history; may contain private code
- `bin/` — platform binaries (`fd`, `rg`); not portable

### Default model

`granite3.3:8b` (131k context). Make sure it's pulled:

```sh
ollama pull granite3.3:8b
```

### Standalone launcher

`scripts/pi-run` wraps `pi` with `PI_OFFLINE=1` to skip version checks and startup network calls — useful on air-gapped machines or when you just want a fast start.

```sh
# interactive
scripts/pi-run

# one-shot headless
scripts/pi-run -p "explain this function" @src/main.ts

# resume last session
scripts/pi-run --continue
```

All other `pi` flags pass through unchanged.

### Settings (`~/.pi/agent/settings.json`)

Key tunables for long-running local sessions:

| Setting | Value | Why |
|---------|-------|-----|
| `retry.provider.timeoutMs` | 600 000 ms | gemma4 can take several minutes per turn |
| `retry.maxRetries` | 5 | agent-level retry with exponential back-off |
| `compaction.enabled` | true | auto-compact at ~72% of the 131k context window |
| `quietStartup` | true | no startup banner in headless/piped use |

### Skills (`~/.pi/agent/skills/`)

Skills are loaded automatically and available as `/skill:name` commands.

| Skill | Trigger |
|-------|---------|
| `git-workflow` | committing, branching, PRs, reviewing diffs |
| `task-planner` | complex multi-step tasks; creates `.pi/task.md` checkpoints for resumable sessions |
| `shell-scripts` | writing or debugging bash/zsh scripts |
| `nvim-config` | editing Lua configs in this repo; headless testing with `luac -p` and `nvim --headless` |
| `supabase` | any Supabase or Postgres work |

Invoke explicitly with `/skill:name args` or let pi pick the right one based on context.

### Long-running sessions

For tasks that span multiple sessions:

1. Start with `/skill:task-planner` — it creates a `.pi/task.md` checklist in the working directory.
2. Resume any time with `pi --continue` (or `scripts/pi-run --continue`).
3. pi auto-compacts context when it approaches the 131k limit, so sessions can run indefinitely.

### Planning → Code → Analysis feedback loop

The workflow I use for non-trivial features and bug fixes:

1. **Plan** — invoke `/skill:task-planner`. It writes a `PLAN.md` in the project root with concrete, checkable steps. Each step has a clear done condition; nothing vague survives.

2. **Code** — invoke `/skill:code-agent`. It picks up `PLAN.md`, works through each `[ ]` task in a tight loop: write code → write test → compile → run → fix until green, then mark `[x]` and commit. It never pauses between increments unless a hard blocker requires input.

3. **Static analysis** — after each task, code-agent runs `sonar-scanner` against a local [SonarQube Community Edition](https://www.sonarsource.com/products/sonarqube/) instance (installed by `scripts/setup.sh` to `/opt/sonarqube`, no Docker). BLOCKER and CRITICAL issues block the task from being marked done — they must be fixed before moving on. MAJOR issues are fixed if local and obvious; otherwise noted. The scanner uses the `sonar-cxx` plugin for C/C++ rule coverage and, for CMake builds, a compilation database for deeper analysis.

4. **Repeat** — the agent loops back to the next `[ ]` in `PLAN.md` without user input until all tasks are `[x]` or a genuine blocker surfaces.

This means the feedback cycle is: plan once → execute autonomously → static analysis gates each increment → commit only clean code. The plan file doubles as a resumable checkpoint — if the session is cut short, `pi --continue` picks up exactly where it left off.

## Switching themes

```sh
bash scripts/switch-theme.sh
```

On first run it clones [tinted-theming/schemes](https://github.com/tinted-theming/schemes) (shallow, base16 only) into `~/.local/share/tinted-theming/schemes` and keeps it up to date on subsequent runs.

Pick a scheme from the fzf list. The preview pane shows the scheme name, author, color swatches for all 16 base16 slots, accent colors on the theme background, and a full hex palette reference.

Confirming a selection rewrites the `config.color_scheme` line in `~/.wezterm.lua`. If your dotfiles copy differs from the live config, the script will ask whether to sync it too. WezTerm reloads immediately; Neovim picks up the change on next start.

**Dependencies:** `git`, `fzf`, `sed`

## How WezTerm and Neovim stay in sync

Neovim reads `~/.wezterm.lua` at startup and looks for the `config.color_scheme` line. As long as the scheme name ends in `(base16)` — like `"Tokyo City Terminal Dark (base16)"` — it translates that into the matching [nvim-base16](https://github.com/RRethy/nvim-base16) name and applies it. If the file isn't there or the scheme doesn't match, it falls back to a classic Borland colorscheme.

That means you only ever set the theme in one place. To switch manually, just edit `.wezterm.lua`:

```lua
config.color_scheme = "Atelier Forest Light (base16)"
```

Any [base16 scheme](https://github.com/tinted-theming/base16-schemes) works. Or use the script above and never touch the file by hand.

## Neovim at a glance

| What | How |
|------|-----|
| Menu bar | `<F10>` (TurboVim) |
| File explorer | `<leader>e` (oil.nvim) |
| Find files | `<leader>ff` |
| Live grep | `<leader>fs` |
| Open buffers | `<leader>fb` |
| Open all folds | `zR` |
| Close all folds | `zM` |
