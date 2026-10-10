# Dotfiles

Turbo Pascal-inspired configuration for Neovim, Midnight Commander, kitty,
zsh, and the [pi](https://pi.dev) coding agent with local Ollama `ministral-3:3b`.

## Install

From the repository root, on macOS, Arch, Debian, or Ubuntu:

```sh
make install
```

This installs dependencies, links configs, and configures Ollama and pi-agent
for `ministral-3:3b`. On macOS,
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

The Neovim config needs Neovim 0.12+ and a Nerd Font. Plugins install on first
launch. See [nvim/DEPENDENCIES.md](nvim/DEPENDENCIES.md) for other tools.

## Included

- **Neovim** — LazyVim with a Turbo Vision UI, LSP, debugging, database tools,
  and pi-agent. Use `:colorscheme turbopascal` for the blue TP7 palette.
- **Midnight Commander** — matching retrobox and Turbo Pascal skins; F4 opens
  Neovim.
- **kitty and zsh** — matching Retrobox terminal colors, a 120×40 kitty layout,
  and a DOS-style prompt.
- **pi** — configured to use Ollama `ministral-3:3b`.

## Local model

```sh
make use-model      # pull and load ministral-3:3b; configure pi-agent
make verify-model   # check that pi writes and runs a C program
```

Reapply Ollama settings with `make install-ollama`.

## Shared configuration and host state

Neovim's `nvim/lazy-lock.json` is tracked so new installations use the same
plugin versions. Update deliberately with `:Lazy update` and commit the
resulting lockfile changes.

`make install-pi` writes only `~/.pi/agent/settings.json` and `models.json` and
links the short shared instructions. Sessions and authentication stay in place.
Set `PI_CODING_AGENT_DIR` to use another pi configuration directory.

Run installer and migration tests with:

```sh
python3 -m unittest discover -s tests -v
```
