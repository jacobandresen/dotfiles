#!/usr/bin/env bash
# turbo-prime.sh — prime the ollama model cache.
#
# USAGE
#   turbo-prime.sh [-h|--help]
#
# DESCRIPTION
#   Pulls every curated model (those listed by `turbo-model.sh models`) so the
#   on-disk cache is fully populated, then loads the configured default model
#   into ollama memory so the first request is instant. Safe to re-run.
#
#   After this, `turbo-model.sh` (or `turbo-model.sh load <id>`) only swaps
#   between models that are already on disk — no network round-trip.
#
# EXIT CODES
#   0   All curated models pulled and the default model is resident
#   1   Bad arguments, ollama unreachable, or a pull failed
#
# CONTACT
#   Jacob Andresen <jacob.andresen@gmail.com>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MICHELLE="$SCRIPT_DIR/../pi/michelle.py"

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

case "${1:-}" in
  -h | --help) usage 0 ;;
  '') ;;
  *) echo "turbo-prime: unexpected argument: $1" >&2; usage 1 ;;
esac

[ -f "$MICHELLE" ] || {
  echo "turbo-prime: cannot find michelle.py at $MICHELLE" >&2
  exit 1
}

command -v ollama >/dev/null 2>&1 || {
  echo "turbo-prime: ollama not found on PATH" >&2
  exit 1
}

# Curated model ids, one per line.
mapfile -t models < <(python3 "$MICHELLE" models --tsv | cut -f2)

if [ "${#models[@]}" -eq 0 ]; then
  echo "turbo-prime: no curated models reported by michelle.py" >&2
  exit 1
fi

echo "Priming on-disk cache for ${#models[@]} curated model(s)..."
for m in "${models[@]}"; do
  echo
  echo "→ ollama pull $m"
  ollama pull "$m"
done

echo
echo "Loading default model into memory..."
exec python3 "$MICHELLE" load
