#!/usr/bin/env bash
# Renders base16 color swatches for an fzf preview pane.
SCHEME_FILE="$1"

[ -f "$SCHEME_FILE" ] || { echo "not found: $SCHEME_FILE"; exit 1; }

get_field() {
  grep -m1 "^${1}:" "$SCHEME_FILE" | sed "s/^${1}:[[:space:]]*//" | tr -d '"' | tr -d "'"
}

get_color() {
  grep -im1 -E "^\s*base${1}:" "$SCHEME_FILE" \
    | sed 's/.*:[[:space:]]*//' | tr -d '"' | tr -d "'" | tr -d '#' | tr -d ' ' | tr -d $'\r'
}

swatch() {
  local hex="$1"
  local r=$((16#${hex:0:2}))
  local g=$((16#${hex:2:2}))
  local b=$((16#${hex:4:2}))
  printf "\e[48;2;%d;%d;%dm   \e[0m" "$r" "$g" "$b"
}

fg_swatch() {
  local fghex="$1" bghex="$2"
  local fr=$((16#${fghex:0:2})) fg=$((16#${fghex:2:2})) fb=$((16#${fghex:4:2}))
  local br=$((16#${bghex:0:2})) bg=$((16#${bghex:2:2})) bb=$((16#${bghex:4:2}))
  printf "\e[38;2;%d;%d;%dm\e[48;2;%d;%d;%dm %s \e[0m" \
    "$fr" "$fg" "$fb" "$br" "$bg" "$bb" "$fghex"
}

name=$(get_field name)
author=$(get_field author)

printf "\n  \e[1m%s\e[0m\n" "${name:-unknown}"
[ -n "$author" ] && printf "  by %s\n" "$author"
printf "\n"

# Collect all 16 hex values
declare -a hexes
for i in {0..15}; do
  slot=$(printf "%02x" "$i")
  hexes[$i]=$(get_color "$slot")
done

# Structural colors (base00–07): two rows of 4
labels_lo=("Background" "Alt Bg" "Selection" "Comments" "Dark Fg" "Foreground" "Light Fg" "Light Bg")
labels_hi=("Red" "Orange" "Yellow" "Green" "Cyan" "Blue" "Magenta" "Brown")

printf "  "
for i in {0..7}; do
  hex="${hexes[$i]}"
  [ -n "$hex" ] && printf "%s" "$(swatch "$hex")" || printf "   "
done
printf "\n  "
for i in {0..7}; do
  printf " %s " "${labels_lo[$i]:0:1}"
done
printf "\n\n  "

for i in {8..15}; do
  hex="${hexes[$i]}"
  [ -n "$hex" ] && printf "%s" "$(swatch "$hex")" || printf "   "
done
printf "\n  "
for i in {8..15}; do
  printf " %s " "${labels_hi[$((i-8))]:0:1}"
done
printf "\n\n"

# Sample: accent colors on the theme background
bg="${hexes[0]}"
if [ -n "$bg" ]; then
  printf "  Accents on background:\n  "
  for i in {8..15}; do
    hex="${hexes[$i]}"
    [ -n "$hex" ] && printf "%s" "$(fg_swatch "$hex" "$bg")" || printf "       "
  done
  printf "\n\n"
fi

# Hex reference
printf "  Palette:\n"
for i in {0..15}; do
  slot=$(printf "%02x" "$i")
  hex="${hexes[$i]}"
  if [ -n "$hex" ]; then
    printf "  %s base%s #%s\n" "$(swatch "$hex")" "$slot" "$hex"
  fi
done
printf "\n"
