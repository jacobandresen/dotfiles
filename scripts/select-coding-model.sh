#!/bin/sh
# Print this host's coding model; override with DOTFILES_CODING_MODEL.
set -eu

if [ -n "${DOTFILES_CODING_MODEL:-}" ]; then
	echo "$DOTFILES_CODING_MODEL"
	exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILE=$("$SCRIPT_DIR/detect-ram-profile.sh")

if [ "$(uname -s)" = "Darwin" ]; then
	# qwen3:4b fits small unified-memory Macs and limits Intel CPU costs.
	echo "qwen3:4b"
else
	case "$PROFILE" in
		32gb) echo "qwen3-coder:30b" ;;
		# qwen3.5 honors think:false for Neovim inline edits.
		*) echo "qwen3.5:4b" ;;
	esac
fi
