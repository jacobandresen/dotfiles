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

exec python3 "$OPTIMIZE" "$@"
