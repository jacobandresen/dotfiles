#!/usr/bin/env bash
set -euo pipefail

SCHEMES_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/tinted-theming/schemes"
WEZTERM_CFG="$(realpath "$HOME/.wezterm.lua" 2>/dev/null || echo "$HOME/.wezterm.lua")"
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
PREVIEW_SCRIPT="$(cd "$(dirname "$0")" && pwd)/preview-theme.sh"

if [ ! -d "$BASE16_DIR" ]; then
  echo "error: base16 schemes not found at $BASE16_DIR" >&2
  exit 1
fi

# Pick a scheme — build "name<TAB>path" pairs so fzf shows the YAML name
# (which matches WezTerm's internal scheme name) while preview gets the path.
chosen=$(
  find "$BASE16_DIR" -name "*.yaml" | while IFS= read -r yaml; do
    name=$(grep -m1 '^name:' "$yaml" | sed 's/^name:[[:space:]]*//' | tr -d '"' | tr -d "'")
    [ -n "$name" ] && printf '%s\t%s\n' "$name" "$yaml"
  done \
    | sort \
    | fzf \
        --delimiter=$'\t' \
        --with-nth=1 \
        --prompt="theme> " \
        --preview="$PREVIEW_SCRIPT {2}" \
        --preview-window="right:45%"
) || exit 0  # user cancelled

[ -z "$chosen" ] && exit 0

scheme_name=$(printf '%s' "$chosen" | cut -f1)
new_line="config.color_scheme = \"$scheme_name (base16)\""

# Update ~/.wezterm.lua
if [ ! -f "$WEZTERM_CFG" ]; then
  echo "error: $WEZTERM_CFG not found" >&2
  exit 1
fi

sed -i '' "s|config\.color_scheme[[:space:]]*=.*|$new_line|" "$WEZTERM_CFG"
echo "updated $WEZTERM_CFG → $scheme_name (base16)"

# Sync dotfiles copy if it differs from the live config
if [ -f "$DOTFILES_CFG" ] && [ "$DOTFILES_CFG" != "$WEZTERM_CFG" ]; then
  if ! diff -q "$WEZTERM_CFG" "$DOTFILES_CFG" &>/dev/null; then
    read -r -p "sync $DOTFILES_CFG too? [y/N] " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      sed -i '' "s|config\.color_scheme[[:space:]]*=.*|$new_line|" "$DOTFILES_CFG"
      echo "updated $DOTFILES_CFG"
    fi
  fi
fi
