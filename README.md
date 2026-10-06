# Dotfiles

Turbo Pascal-inspired configs with a modern twist for Neovim, Midnight
Commander, kitty, zsh and the [pi](https://pi.dev) coding agent with local
[Ollama](https://ollama.com) models.

## Install

```sh
make install
```

The installer detects the host OS and RAM profile, installs dependencies,
links shared configs, keeps Pi runtime settings local to the host, and applies
matching Ollama and Docker limits. On macOS,
Docker Desktop is opt-in:

```sh
make deps-docker-macos
```

`make deps` installs the CLI tools, Oh My Zsh, terminal/editor dependencies,
and a Nerd Font. Debian and Ubuntu use upstream Neovim binaries when the
installed version is older than 0.12; no Ubuntu PPA is added on Debian.
Override the binary release with `NEOVIM_VERSION=<tag>` when needed.

Check the installed tools without making changes:

```sh
make doctor
```

Requires Git, Neovim 0.12+, and a Nerd Font. Neovim plugins install on first
launch. See [nvim/DEPENDENCIES.md](nvim/DEPENDENCIES.md) for Neovim tools.

## Included

- **Neovim** — LazyVim with a Turbo Vision UI, LSP, debugging, database tools
  and AI integrations. Use `:colorscheme turbopascal` for the blue TP7 palette.
- **Midnight Commander** — matching retrobox and Turbo Pascal skins; F4 opens
  Neovim.
- **kitty, GNOME Terminal and zsh** — matching Retrobox terminal colors, a
  120×40 kitty layout and DOS-style prompt. On Linux, `make install` creates
  and selects the GNOME Terminal Retrobox profile.
- **pi** — configured to use the host's selected Ollama model.

## Model controls

```sh
make ram-profile                  # show the detected profile and model
make use-model MODEL=<tag>       # switch pi, Neovim and mu
make use-model                    # restore the host-selected model
make verify-model                 # build and run a generated C program
make install-ollama install-docker
```

The last command reapplies the host's resource profile after a hardware or
configuration change.

## Shared configuration and host state

Neovim's `nvim/lazy-lock.json` is tracked so new installations use the same
plugin versions. Update deliberately with `:Lazy update` and commit the
resulting lockfile changes.

Pi's shared model catalog is `pi/agent/models.json`; it has no host-selected
`_launch` flag. `make install-pi` seeds host-local `~/.pi/agent/models.json` and
`settings.json`, and `make setup-host` or `make use-model` updates those local
files. The host-local catalog caps each model's advertised context to the
configured Ollama context (8K on Linux, 16K on macOS by default); override this
with `DOTFILES_OLLAMA_CONTEXT_LENGTH` when using a custom server profile.
Shared instructions and skills remain linked to this repository.
`PI_CODING_AGENT_DIR` is supported for a custom configuration directory.

Existing `~/.pi -> dotfiles/pi` installations migrate on the next
`make install-pi` or `make setup-host`: data is copied into a real `~/.pi`
directory and the old symlink is preserved as `~/.pi.dotfiles-link.bak`
(with an additional `.bak` suffix if that name already exists). Existing
sessions, authentication, custom settings, and installed packages are kept.
The ignored legacy runtime files in the repository are retained as well.
Preview this migration with `python3 scripts/install-pi-config.py --dry-run`.

Run migration regression tests with:

```sh
python3 -m unittest discover -s tests -v
```
