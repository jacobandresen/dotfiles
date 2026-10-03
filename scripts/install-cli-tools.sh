#!/usr/bin/env bash
# Package managers provide the prerequisites; install only missing extras.
set -euo pipefail
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
if [ ! -f "${ZSH:-$HOME/.oh-my-zsh}/oh-my-zsh.sh" ]; then
  git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "${ZSH:-$HOME/.oh-my-zsh}"
fi
# Debian names the fd executable fdfind.
if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
  mkdir -p "$HOME/.local/bin"
  if [ ! -e "$HOME/.local/bin/fd" ] && [ ! -L "$HOME/.local/bin/fd" ]; then
    ln -s "$(command -v fdfind)" "$HOME/.local/bin/fd"
  fi
fi
if ! command -v pi >/dev/null 2>&1; then
  if [ -d "$HOME/.npm" ] && [ -n "$(find "$HOME/.npm" ! -user "$(id -un)" -print -quit 2>/dev/null)" ]; then
    echo "~/.npm has files owned by another user; fix their ownership before installing Pi" >&2
    exit 1
  fi
  curl -fSL https://pi.dev/install.sh -o "$work/pi.sh"
  bash "$work/pi.sh"
fi
if ! command -v ollama >/dev/null 2>&1; then
  if [ "$(uname -s)" = Darwin ]; then
    echo "Install Ollama with: brew install --cask ollama" >&2; exit 1
  fi
  curl -fSL https://ollama.com/install.sh -o "$work/ollama.sh"
  sh "$work/ollama.sh"
fi
if ! command -v lazydocker >/dev/null 2>&1; then
  if [ "$(uname -s)" = Darwin ]; then
    brew install lazydocker
  else
    curl -fSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh -o "$work/lazydocker.sh"
    bash "$work/lazydocker.sh"
  fi
fi
