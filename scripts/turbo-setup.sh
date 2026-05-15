#!/bin/sh
set -e

IS_WSL=0
case "$(uname -r)" in *microsoft* | *Microsoft*) IS_WSL=1 ;; esac

if [ "$(uname)" = "Darwin" ]; then
  brew install neovim make gcc llvm node python jq git fpc fzf ripgrep fd ollama
  # clang-tidy ships inside llvm; symlink it into PATH if not already there
  LLVM_BIN="$(brew --prefix llvm)/bin"
  if [ ! -e /usr/local/bin/clang-tidy ] && [ -f "${LLVM_BIN}/clang-tidy" ]; then
    sudo ln -sf "${LLVM_BIN}/clang-tidy" /usr/local/bin/clang-tidy
  fi
  brew install --cask font-terminess-ttf-nerd-font
elif [ -f /etc/arch-release ]; then
  sudo pacman -S --needed neovim ttf-terminus-nerd base-devel make gcc clang nodejs npm python jq git fpc fzf wl-clipboard ripgrep fd ollama unzip
elif [ -f /etc/debian_version ]; then
  sudo apt-get update
  # The apt neovim is often outdated; use the upstream PPA for a recent stable release
  sudo apt-get install -y software-properties-common
  sudo add-apt-repository -y ppa:neovim-ppa/stable
  sudo apt-get update
  sudo apt-get install -y neovim build-essential make gcc clang clang-tidy nodejs npm python3 jq git fpc fzf ripgrep fd-find unzip
  # fd-find ships the binary as 'fdfind'; symlink to 'fd' so tools can find it
  if command -v fdfind > /dev/null 2>&1 && [ ! -e /usr/local/bin/fd ]; then
    sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd
  fi
  # ollama — official install script (covers x86-64 and arm64)
  echo "Downloading ollama installer..."
  curl -fL# https://ollama.com/install.sh | sh
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

# AI backend — installed via npm on all platforms
npm install -g @earendil-works/pi-coding-agent

# Pull the default local model (ollama auto-starts its server if needed)
ollama pull gemma4
