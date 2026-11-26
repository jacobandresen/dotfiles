# Dotfiles

Retro terminal setup for Neovim, Midnight Commander, kitty and zsh, plus the
[pi](https://pi.dev) coding agent running JetBrains Mellum 2.1 on local Ollama
(Qwen and selected GitHub Copilot models as alternatives).

## Install

On macOS, Arch, Debian or Ubuntu, from the repository root:

```sh
make install   # dependencies, config links, Ollama and pi with mellum
make doctor    # check the installed tools, changing nothing
```

- `make deps` installs tools without linking configs.
- `make deps-docker-macos` adds the optional Docker Desktop on macOS.
- Debian and Ubuntu get a SHA-256-verified Neovim release when theirs is older than 0.12.

Neovim needs 0.12+ and Hack Nerd Font Mono (`make install-fonts`). Plugins install
on first launch; other tools are listed in [nvim/DEPENDENCIES.md](nvim/DEPENDENCIES.md).

## Included

- **Neovim**: LazyVim with the dark Retrobox theme, LSP, inline FIM completions from
  Ollama, debugging, database tools, and a matching pi terminal.
- **[taskbay.nvim](https://github.com/jacobandresen/taskbay.nvim)**: several pi agents
  at once, each in its own worktree; `Space a w` is the hub
  ([nvim/README.md](nvim/README.md#tasks-taskbay)).
- **Midnight Commander**: matching Retrobox and Turbo Pascal skins; F4 opens Neovim.
- **kitty and zsh**: Hack Nerd Font Mono, Catppuccin Latte colours, a 120×40 layout,
  a DOS-style prompt and a cat-eared `λ ~/` launcher icon.
- **pi**: Ollama `mellum` by default; Qwen 3.5 9B and the GitHub Copilot models
  GPT-6.1 Sol and Claude Opus 5.5 as alternatives.
- **git-pi**: `git-pi start <issue>` starts pi in a fresh worktree from any
  terminal; `git-pi list` and `git-pi diff` show what's running and what changed.

## Local model

```sh
make use-model      # pull Mellum 2.1, configure and warm pi
make verify-model   # check that pi writes and runs a C program
make install-ollama # reapply the Ollama settings
```

The warmed model stays loaded until Ollama stops or loads another one.

## Host state

- Neovim plugins have no tracked lockfile; update them with `:Lazy update`.
- `make install-pi` writes only `~/.pi/agent/settings.json` and `models.json` and
  links the shared instructions; sessions and logins stay. `PI_CODING_AGENT_DIR`
  selects another pi config directory.

Installer tests: `python3 -m unittest discover -s tests -v`
