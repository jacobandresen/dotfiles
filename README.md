# Dotfiles

Turbo Pascal-inspired configuration for Neovim, Midnight Commander, kitty,
zsh, and the [pi](https://pi.dev) coding agent with local [Ollama](https://ollama.com) models.

## Install

From the repository root, on macOS, Arch, Debian, or Ubuntu:

```sh
make install
```

This installs dependencies, links configs, selects Ollama and Docker resource
profiles based on RAM, and keeps pi settings local to the host. On macOS,
Docker Desktop is optional:

```sh
make deps-docker-macos
```

`make deps` installs tools without linking configs. Debian and Ubuntu use an
upstream Neovim binary when the installed version is older than 0.12. Set
`NEOVIM_VERSION=<tag>` to select a specific release.

Check the installed tools without making changes:

```sh
make doctor
```

The Neovim config needs Neovim 0.12+ and a Nerd Font. Plugins install on first
launch. See [nvim/DEPENDENCIES.md](nvim/DEPENDENCIES.md) for other tools.

## Included

- **Neovim** — LazyVim with a Turbo Vision UI, LSP, debugging, database tools
  and AI integrations. Use `:colorscheme turbopascal` for the blue TP7 palette.
- **Midnight Commander** — matching retrobox and Turbo Pascal skins; F4 opens
  Neovim.
- **kitty and zsh** — matching Retrobox terminal colors, a 120×40 kitty layout,
  and a DOS-style prompt.
- **pi** — configured to use the host's selected Ollama model.

## Model controls

```sh
make ram-profile             # show the RAM profile and selected model
make use-model MODEL=<tag>  # pull and load a model; configure pi to use it
make use-model               # restore the host-selected model
make setup-host              # configure pi without pulling a model
make verify-model            # check that pi writes and runs a C program
```

Neovim uses the model currently loaded in Ollama. Reapply resource limits after
a hardware or configuration change with `make install-ollama install-docker`.

## Shared configuration and host state

Neovim's `nvim/lazy-lock.json` is tracked so new installations use the same
plugin versions. Update deliberately with `:Lazy update` and commit the
resulting lockfile changes.

The shared pi model catalog is `pi/agent/models.json`. `make install-pi` creates
host-local `~/.pi/agent/models.json` and `settings.json`; `make setup-host` and
`make use-model` update those files. Shared instructions and skills stay linked
to this repository. Set `PI_CODING_AGENT_DIR` for another config directory.
The host-local catalog caps context at 8K on Linux or 16K on macOS by default;
set `DOTFILES_OLLAMA_CONTEXT_LENGTH` for a custom Ollama context.

For older `~/.pi -> dotfiles/pi` installations, `make install-pi` or
`make setup-host` copies runtime data into a real `~/.pi` directory and saves
the old link as `~/.pi.dotfiles-link.bak` (adding another `.bak` if needed).
Sessions, authentication, settings, and packages are preserved. Preview with
`python3 scripts/pi_config.py --dry-run`.

Run installer and migration tests with:

```sh
python3 -m unittest discover -s tests -v
```
