#!/bin/sh
# turbo-optimize.sh — tune ollama for turbo-ralph's sequential workload.
#
# USAGE
#   turbo-optimize.sh [-h|--help]
#
# DESCRIPTION
#   Tunes ollama for turbo-ralph's sequential one-file-per-call workload,
#   assuming the working model is already pulled and resident (cache primed).
#   Detects CPU, RAM and GPU, computes settings for a single resident model
#   (1–2 parallel slots, 4k per-slot context, q8_0 KV cache, deep queue,
#   keep-alive 5 min on low-RAM / forever on mid+high, flash attention),
#   writes a systemd service override (Linux) or updates the launchd plist
#   (macOS), pins the CPU governor to performance when available, and restarts
#   ollama.
#
#   Thin wrapper around pi/optimize.py.
#
# EXIT CODES
#   0   Optimization applied successfully
#   1   Bad arguments or optimize.py reported an error
#
# CONTACT
#   Jacob Andresen <jacob.andresen@gmail.com>

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPTIMIZE="$SCRIPT_DIR/../pi/optimize.py"

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

case "${1:-}" in
  -h | --help) usage 0 ;;
esac

[ -f "$OPTIMIZE" ] || {
  echo "turbo-optimize: cannot find optimize.py at $OPTIMIZE" >&2
  exit 1
}

# Write OLLAMA env vars to the default shell's rc file if not already set.
_default_shell="$(basename "${SHELL:-}")"
case "$_default_shell" in
  zsh)  _rc="$HOME/.zshrc" ;;
  bash) _rc="$HOME/.bashrc" ;;
  *)
    printf 'turbo-optimize: unsupported default shell "%s" — set manually:\n' "$_default_shell" >&2
    printf '  export OLLAMA_MAX_RAM=6GB\n  export OLLAMA_NUM_PARALLEL=1\n' >&2
    _rc="" ;;
esac

if [ -n "$_rc" ]; then
  _wrote=0
  if ! grep -q 'OLLAMA_MAX_RAM' "$_rc" 2>/dev/null; then
    printf '\nexport OLLAMA_MAX_RAM=6GB\n' >> "$_rc"
    _wrote=1
  fi
  if ! grep -q 'OLLAMA_NUM_PARALLEL' "$_rc" 2>/dev/null; then
    printf 'export OLLAMA_NUM_PARALLEL=1\n' >> "$_rc"
    _wrote=1
  fi
  if [ "$_wrote" -eq 1 ]; then
    echo "turbo-optimize: Ollama env vars written to $_rc — run: source $_rc"
  else
    echo "turbo-optimize: Ollama env vars already present in $_rc"
  fi
fi

exec python3 "$OPTIMIZE" "$@"
