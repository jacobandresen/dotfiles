#!/bin/sh
# Picks the best local coding model for pi agent based on the machine's
# RAM profile (see detect-ram-profile.sh). Prints the ollama model tag.
#
# 32gb: qwen3-coder:30b — Qwen3-Coder (30B/3.3B active MoE), best local
#       agentic coding model that comfortably fits alongside the 32gb
#       ollama override profile.
# 16gb: qwen2.5-coder:14b — strong coding model that fits comfortably
#       within the more conservative 16gb ollama override profile.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILE=$("$SCRIPT_DIR/detect-ram-profile.sh")

case "$PROFILE" in
	32gb) echo "qwen3-coder:30b" ;;
	*) echo "qwen2.5-coder:14b" ;;
esac
