#!/usr/bin/env bash
set -euo pipefail

SCHEMES_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/tinted-theming/schemes"
BASE16_DIR="$SCHEMES_DIR/base16"
WEZTERM_CFG="$HOME/.wezterm.lua"
DOTFILES_CFG="$(cd "$(dirname "$0")/.." && pwd)/.wezterm.lua"
THEME_LUA="$(cd "$(dirname "$0")" && pwd)/theme.lua"

for cmd in git fzf lua; do
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

[ -d "$BASE16_DIR" ] || { echo "error: base16 schemes not found at $BASE16_DIR" >&2; exit 1; }

chosen=$(
  lua "$THEME_LUA" list "$BASE16_DIR" \
    | fzf \
        --delimiter=$'\t' \
        --with-nth=1 \
        --prompt="theme> " \
        --preview="lua $THEME_LUA preview {2}" \
        --preview-window="right:45%"
) || exit 0

[ -z "$chosen" ] && exit 0

scheme_name=$(printf '%s' "$chosen" | cut -f1)

[ -f "$WEZTERM_CFG" ] || { echo "error: $WEZTERM_CFG not found" >&2; exit 1; }

lua "$THEME_LUA" set "$WEZTERM_CFG" "$scheme_name"
echo "updated $WEZTERM_CFG → $scheme_name (base16)"

# Sync dotfiles copy if it differs from the live config
if [ -f "$DOTFILES_CFG" ] && [ "$DOTFILES_CFG" != "$WEZTERM_CFG" ]; then
  if ! diff -q "$WEZTERM_CFG" "$DOTFILES_CFG" &>/dev/null; then
    read -r -p "sync $DOTFILES_CFG too? [y/N] " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      lua "$THEME_LUA" set "$DOTFILES_CFG" "$scheme_name"
      echo "updated $DOTFILES_CFG"
    fi
  fi
fi
