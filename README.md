# Dotfiles

Retro terminal configuration for Neovim, Midnight Commander, kitty, zsh, and
the [pi](https://pi.dev) coding agent with local Ollama `qwen3.5-coding:4b`.

## Install

From the repository root, on macOS, Arch, Debian, or Ubuntu:

```sh
make install
```

This installs dependencies, links configs, and configures Ollama and pi-agent
for `qwen3.5-coding:4b`. On macOS,
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

The Neovim config needs Neovim 0.12+ and BigBlueTermPlus Nerd Font Mono,
installed by `make deps` or `make install-fonts`. Plugins install on first
launch. See [nvim/DEPENDENCIES.md](nvim/DEPENDENCIES.md) for other tools.

## Included

- **Neovim** — LazyVim with the dark Retrobox theme, LSP, debugging,
  database tools, and a matching pi-agent terminal.
- **Midnight Commander** — matching retrobox and Turbo Pascal skins; F4 opens
  Neovim.
- **kitty and zsh** — BigBlueTermPlus Nerd Font Mono, matching retro terminal
  colors, a 120×40 kitty layout, a DOS-style prompt, and a cat-eared `λ ~/`
  launcher icon (`kitty.app.png` on macOS).
- **pi** — configured to use Ollama `qwen3.5-coding:4b`.

## Local model

```sh
make use-model      # pull Qwen 3.5 4B Q4, create the 16K coding model, configure pi
make verify-model   # check that pi writes and runs a C program
```

`make use-model` keeps the 16K coding model loaded for quick replies, using about
3.5 GB of VRAM until Ollama stops or loads another model.

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
