#!/bin/sh
# turbo-model.sh — manage the ollama model used by the pi agent.
#
# USAGE
#   turbo-model.sh [COMMAND] [ARGS...]
#
# COMMANDS
#   (none)                   Show this help and exit
#   load [OPTS]              Load the default model into ollama memory (keep_alive=30m)
#   unload [OPTS]            Spin down the default model (keep it installed)
#   set-default <model>      Switch the pi + ollama default model
#   enforce [--model M]      Keep only the default model installed
#   status                   Show installed models and agent config
#   optimize                 Tune ollama for the host hardware
#   move-storage             Move /var/lib/ollama -> /opt/ollama
#
# OPTIONS
#   -h, --help               Show this help and exit
#
# DESCRIPTION
#   Thin wrapper around pi/michelle.py. With no arguments, prints this
#   help. Any subcommand and its flags are forwarded to michelle.py
#   unchanged — run `turbo-model.sh <command> --help` for per-command
#   options.
#
# EXIT CODES
#   0   Command succeeded
#   1   Bad arguments or michelle.py reported an error
#
# CONTACT
#   Jacob Andresen <jacob.andresen@gmail.com>

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MICHELLE="$SCRIPT_DIR/../pi/michelle.py"

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

case "${1:-}" in
  '' | -h | --help) usage 0 ;;
esac

[ -f "$MICHELLE" ] || {
  echo "turbo-model: cannot find michelle.py at $MICHELLE" >&2
  exit 1
}

exec python3 "$MICHELLE" "$@"
