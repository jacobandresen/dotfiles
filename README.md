# Dotfiles

Retro terminal configuration for Neovim, Midnight Commander, kitty, zsh, and
the [pi](https://pi.dev) coding agent with JetBrains Mellum 2.1 through local
Ollama, with Qwen and selected GitHub Copilot models available as alternatives.

## Install

From the repository root, on macOS, Arch, Debian, or Ubuntu:

```sh
make install
```

This installs dependencies, links configs, and configures Ollama and pi-agent
for `mellum`. On macOS,
Docker Desktop is optional:

```sh
make deps-docker-macos
```

`make deps` installs tools without linking configs. Debian and Ubuntu use a
SHA-256 verified Neovim release when the installed version is older than 0.12.

Check the installed tools without making changes:

```sh
make doctor
```

The Neovim config needs Neovim 0.12+ and Hack Nerd Font Mono,
installed by `make deps` or `make install-fonts`. Plugins install on first
launch. See [nvim/DEPENDENCIES.md](nvim/DEPENDENCIES.md) for other tools.

## Included

- **Neovim** — LazyVim with the dark Retrobox theme, LSP, inline FIM
  completions from Ollama, debugging, database tools, and a matching pi-agent
  terminal.
- **Midnight Commander** — matching retrobox and Turbo Pascal skins; F4 opens
  Neovim.
- **kitty and zsh** — Hack Nerd Font Mono, matching Catppuccin Latte terminal
  colors, a 120×40 kitty layout, a DOS-style prompt, and a cat-eared `λ ~/`
  launcher icon (`kitty.app.png` on macOS).
- **pi** — configured to use Ollama `mellum` by default, with Qwen 3.5 9B and
  GitHub Copilot GPT-6.1 Sol and Claude Opus 5.5 available as alternatives.
- **Issue worktrees** — `git-pi start <issue>` creates an isolated worktree
  and starts pi in it. Run the command in separate terminal tabs for several
  issues; `git-pi list` shows them and `git-pi diff` gives a compact change
  summary.

## Local model

```sh
make use-model      # pull Mellum 2.1, configure and warm pi
make verify-model   # check that pi writes and runs a C program
```

`make use-model` keeps the model loaded for quick replies until Ollama stops or
loads another model.

Reapply Ollama settings with `make install-ollama`.

## Shared configuration and host state

Neovim plugins are managed by lazy.nvim without a tracked lockfile. Update
them deliberately with `:Lazy update`.

`make install-pi` writes only `~/.pi/agent/settings.json` and `models.json` and
links the short shared instructions. Sessions and authentication stay in place.
Set `PI_CODING_AGENT_DIR` to use another pi configuration directory.

Run installer and migration tests with:

```sh
python3 -m unittest discover -s tests -v
```
