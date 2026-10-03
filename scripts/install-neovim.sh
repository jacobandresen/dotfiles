#!/usr/bin/env bash
# Install an upstream Linux binary when the existing Neovim is too old.
set -euo pipefail
compatible() {
  "$1" --version | python3 -c 'import re,sys; m=re.search(r"NVIM v(\d+)\.(\d+)", sys.stdin.read()); sys.exit(0 if m and tuple(map(int,m.groups())) >= (0,12) else 1)'
}
if command -v nvim >/dev/null 2>&1 && compatible nvim; then
  echo "Neovim >= 0.12 is already installed"
  exit 0
fi
case "$(uname -m)" in
  x86_64) arch=x86_64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo "Unsupported Neovim binary architecture: $(uname -m)" >&2; exit 1 ;;
esac
version="${NEOVIM_VERSION:-stable}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
archive="nvim-linux-$arch"
curl -fSL "https://github.com/neovim/neovim/releases/download/$version/$archive.tar.gz" -o "$work/nvim.tar.gz"
tar -xzf "$work/nvim.tar.gz" -C "$work"
compatible "$work/$archive/bin/nvim" || {
  echo "This release is older than 0.12; set NEOVIM_VERSION to a compatible release tag" >&2; exit 1;
}
# Versioned paths preserve previous installs and avoid partial replacements.
destination="$HOME/.local/share/neovim/$("$work/$archive/bin/nvim" --version | sed -n '1p' | tr ' /' '__')-$arch"
mkdir -p "$destination" "$HOME/.local/bin"
cp -R "$work/$archive/." "$destination/"
if [ -e "$HOME/.local/bin/nvim" ] && [ ! -L "$HOME/.local/bin/nvim" ]; then
  echo "Refusing to overwrite an existing ~/.local/bin/nvim executable" >&2; exit 1
fi
ln -sfn "$destination/bin/nvim" "$HOME/.local/bin/nvim"
echo "Installed Neovim in $destination"
