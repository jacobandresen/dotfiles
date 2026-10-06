#!/usr/bin/env bash
# Compatibility entry point for pulling/loading a model without configuring Pi.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
args=(--ollama-only --keepalive 24h)
model=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		-h|--help)
			printf '%s\n' "Usage: $(basename "$0") [OPTIONS] [MODEL]" \
				"Pull and load the selected model without changing Pi settings." \
				"  -n, --dry-run  Show actions without making changes" \
				"  -v, --verbose  Accepted for compatibility"
			exit 0
			;;
		-n|--dry-run|-v|--verbose) args+=("$1") ;;
		-*) echo "Unknown option: $1" >&2; exit 1 ;;
		*)
			if [[ -n "$model" ]]; then echo "Only one model may be specified" >&2; exit 1; fi
			model="$1"
			;;
	esac
	shift
done

if [[ -n "$model" ]]; then args+=("$model"); fi
exec "$SCRIPT_DIR/use-model.sh" "${args[@]}"
