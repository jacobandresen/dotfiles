#!/bin/sh
set -e

IS_WSL=0
case "$(uname -r)" in *microsoft* | *Microsoft*) IS_WSL=1 ;; esac

if [ "$(uname)" = "Darwin" ]; then
  brew install neovim make gcc node python jq git fpc fzf
  brew install --cask font-terminess-ttf-nerd-font
elif [ -f /etc/arch-release ]; then
  sudo pacman -S --needed neovim ttf-terminus-nerd base-devel make gcc nodejs npm python jq git fpc fzf wl-clipboard
elif [ -f /etc/debian_version ]; then
  sudo apt-get update
  # The apt neovim is often outdated; use the upstream PPA for a recent stable release
  sudo apt-get install -y software-properties-common
  sudo add-apt-repository -y ppa:neovim-ppa/stable
  sudo apt-get update
  sudo apt-get install -y neovim build-essential make gcc nodejs npm python3 jq git fpc fzf
  if [ "$IS_WSL" = "1" ]; then
    echo "Note: install Terminess Nerd Font on your Windows host (not inside WSL)."
    echo "Download TerminessTTF from https://www.nerdfonts.com/font-downloads and install via Windows Font Settings."
  else
    echo "Note: install Terminess Nerd Font manually."
    echo "Download TerminessTTF from https://www.nerdfonts.com/font-downloads"
  fi
else
  echo "Unsupported OS" >&2
  exit 1
fi
