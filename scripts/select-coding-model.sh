#!/bin/sh
# Picks the best local coding model for pi agent on this machine and prints
# the ollama model tag. Consumed by the Makefile (install-pi, ram-profile)
# and by setup-model.sh.
#
# Selection keys off two things: the RAM profile (see detect-ram-profile.sh)
# and, on macOS, the memory architecture.
#
# Why macOS differs from Linux at the same RAM size:
#
#   Apple silicon has *unified* memory — the GPU allocation comes out of the
#   same pool as the OS, the browser and the editor, and Ollama can only wire
#   down about 75% of it (sysctl iogpu.wired_limit_mb, 0 = default). A Linux
#   box with a 16GB discrete GPU has 16GB of VRAM *plus* its system RAM; a
#   16GB Mac does not. So the Mac tiers are deliberately one step more
#   conservative than the Linux tiers at the same nominal RAM.
#
#   Intel Macs have no usable Ollama GPU path in practice, so inference is
#   CPU-bound and large models are unusably slow regardless of free RAM.
#   They stay small no matter how much memory is installed.
#
# Override for a one-off or an unusual host:
#   DOTFILES_CODING_MODEL=qwen2.5-coder:7b make install-pi

set -eu

if [ -n "${DOTFILES_CODING_MODEL:-}" ]; then
	echo "$DOTFILES_CODING_MODEL"
	exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILE=$("$SCRIPT_DIR/detect-ram-profile.sh")

if [ "$(uname -s)" = "Darwin" ]; then
	if [ "$(uname -m)" = "arm64" ]; then
		# Apple silicon, unified memory (~75% wirable by the GPU).
		case "$PROFILE" in
			# ~18GB at q4 for the 30B/3.3B-active MoE — fits the ~24GB
			# wirable on a 32GB Mac, and only 3.3B params are active so
			# it stays fast.
			32gb) echo "qwen3-coder:30b" ;;
			# 7b (~4.7GB at q4), not the 14b the Linux tier uses: 14b is
			# ~9GB before the KV cache, which leaves nothing for the OS
			# inside a 16GB Mac's ~12GB wirable budget.
			16gb) echo "qwen2.5-coder:7b" ;;
			# ~1.9GB at q4, leaving room for macOS (3-4GB) and an editor.
			*) echo "qwen2.5-coder:3b" ;;
		esac
	else
		# Intel Mac: CPU-bound inference, so size for latency, not RAM.
		case "$PROFILE" in
			32gb) echo "qwen2.5-coder:7b" ;;
			*) echo "qwen2.5-coder:3b" ;;
		esac
	fi
else
	# Linux, typically with a discrete GPU whose VRAM is separate from
	# system RAM, so the same nominal RAM tier can carry a larger model.
	case "$PROFILE" in
		32gb) echo "qwen3-coder:30b" ;;
		16gb) echo "qwen2.5-coder:14b" ;;
		*) echo "qwen2.5-coder:3b" ;;
	esac
fi
