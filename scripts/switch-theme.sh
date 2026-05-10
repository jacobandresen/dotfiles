#!/usr/bin/env bash
set -euo pipefail

SCHEMES_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/tinted-theming/schemes"
WEZTERM_CFG="$HOME/.wezterm.lua"
DOTFILES_CFG="$(cd "$(dirname "$0")/.." && pwd)/.wezterm.lua"

# Dependencies
for cmd in git fzf sed; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "error: $cmd is required but not installed" >&2
    exit 1
  fi
done

# Clone or update the schemes repo (base16 only, shallow)
if [ -d "$SCHEMES_DIR/.git" ]; then
  git -C "$SCHEMES_DIR" pull --quiet --ff-only
else
  mkdir -p "$(dirname "$SCHEMES_DIR")"
  git clone --depth 1 --filter=blob:none --sparse \
    https://github.com/tinted-theming/schemes "$SCHEMES_DIR" --quiet
  git -C "$SCHEMES_DIR" sparse-checkout set base16
fi

BASE16_DIR="$SCHEMES_DIR/base16"

if [ ! -d "$BASE16_DIR" ]; then
  echo "error: base16 schemes not found at $BASE16_DIR" >&2
  exit 1
fi

# Pick a scheme
chosen=$(
  find "$BASE16_DIR" -name "*.yaml" -printf "%f\n" \
    | sed 's/\.yaml$//' \
    | sort \
    | fzf \
        --prompt="theme> " \
        --preview="cat $BASE16_DIR/{}.yaml" \
        --preview-window="right:50%:wrap"
) || exit 0  # user cancelled

[ -z "$chosen" ] && exit 0

new_line="config.color_scheme = \"$chosen (base16)\""

# Update ~/.wezterm.lua
if [ ! -f "$WEZTERM_CFG" ]; then
  echo "error: $WEZTERM_CFG not found" >&2
  exit 1
fi

sed -i "s|config\.color_scheme\s*=.*|$new_line|" "$WEZTERM_CFG"
echo "updated $WEZTERM_CFG → $chosen (base16)"

# Sync dotfiles copy if it differs from the live config
if [ -f "$DOTFILES_CFG" ] && [ "$DOTFILES_CFG" != "$WEZTERM_CFG" ]; then
  if ! diff -q "$WEZTERM_CFG" "$DOTFILES_CFG" &>/dev/null; then
    read -r -p "sync $DOTFILES_CFG too? [y/N] " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      sed -i "s|config\.color_scheme\s*=.*|$new_line|" "$DOTFILES_CFG"
      echo "updated $DOTFILES_CFG"
    fi
  fi
fi
