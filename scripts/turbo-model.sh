#!/usr/bin/env bash
# turbo-model.sh — manage the ollama model used by the pi agent.
#
# USAGE
#   turbo-model.sh                    Pick a curated model with fzf and load it
#   turbo-model.sh [COMMAND] [ARGS]   Forward to pi/michelle.py
#
# COMMANDS
#   (none)                   Open fzf picker; load the selected model
#   load [MODEL] [OPTS]      Pull (if needed), set as default, unload others, load it
#   unload [OPTS]            Spin down the default model (keep it installed)
#   models [--tsv]           List the curated set of small-GPU-friendly models
#   status                   Show installed models and agent config
#   move-storage             Move /var/lib/ollama -> /opt/ollama
#
# OPTIONS
#   -h, --help               Show this help and exit
#
# DESCRIPTION
#   With no arguments, opens an fzf picker over the curated set of small-GPU
#   models (description, context, install/default markers). Selecting one
#   invokes `michelle.py load <model>`. Any explicit subcommand is forwarded
#   to michelle.py — run `turbo-model.sh <command> --help` for per-command
#   options.
#
# EXIT CODES
#   0   Command (or picker) succeeded; picker cancelled also returns 0
#   1   Bad arguments or michelle.py reported an error
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
esac

[ -f "$MICHELLE" ] || {
  echo "turbo-model: cannot find michelle.py at $MICHELLE" >&2
  exit 1
}

# Any explicit subcommand → forward verbatim.
if [ "$#" -gt 0 ]; then
  exec python3 "$MICHELLE" "$@"
fi

# No args → interactive picker.
if ! command -v fzf >/dev/null 2>&1; then
  echo "error: fzf is required for the interactive picker" >&2
  exit 1
fi

chosen=$(
  python3 "$MICHELLE" models --tsv \
    | fzf \
        --delimiter=$'\t' \
        --with-nth=1 \
        --prompt="model> " \
        --preview="python3 $MICHELLE model-info {2}" \
        --preview-window="right:50%"
) || exit 0

[ -z "$chosen" ] && exit 0

model_id=$(printf '%s' "$chosen" | cut -f2)
exec python3 "$MICHELLE" load "$model_id"
