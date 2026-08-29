#!/bin/sh
# Picks the best local coding model for pi agent on this machine and prints
# the ollama model tag. Consumed by the Makefile (install-pi, ram-profile)
# and by setup-model.sh.
#
# Selection keys off three things: whether the model can actually drive pi
# to a working program, the RAM profile (see detect-ram-profile.sh), and, on
# macOS, the memory architecture.
#
# Why capability comes before size:
#
#   pi is an agent — it only touches files by calling its write/edit/bash
#   tools. A model that cannot do that end to end is not "slightly worse" at
#   this job, it is useless for it, and it fails *silently*: the transcript
#   shows tool calls and confident prose while nothing usable reaches disk.
#
#   There are three separate ways to fail, and only the last test catches
#   all of them. scripts/verify-agent-model.sh is that test — it asks pi for
#   a hello world in C and then compiles and runs the artifact. Measured on
#   this repo's hardware:
#
#     qwen2.5-coder:3b   emits no tool call, just fenced JSON  -> unusable
#     qwen2.5-coder:7b   same; `ollama show` advertises tools  -> unusable
#     llama3.2:3b        passes a one-tool curl probe, then
#                        reverts to text mimicry under pi's
#                        real prompt                           -> unusable
#     llama3.1:8b        real tool calls, mangled arguments:
#                        writes the two characters \n into the
#                        file and drops #include <stdio.h>, so
#                        the C never compiles                  -> unusable
#     qwen3:4b           writes valid C, compiles, runs        -> works
#     qwen3:8b           same, at the 16GB tier                -> works
#
#   The llama3.1:8b row is why the bar is the compiled artifact and not the
#   transcript. It was this repo's pick for exactly that reason: it got
#   further than anything else and still never produced a program.
#
#   Ollama declaring a `tools` capability (`ollama show <model>`) predicts
#   none of this, and neither does a one-tool probe. Verify a candidate with
#   verify-agent-model.sh before adopting it.
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
#   CPU-bound. They get the 4b at every size: it is the smallest tag that
#   passes, so it is also the least painful thing to run on a CPU.
#
# The 8GB tier finally fits:
#
#   qwen3:4b is 3.9GB resident at the 16K context this repo configures, and
#   benches at 100% GPU on an 8GB M2 with no swap growth (29 tok/s). The
#   previous pick (llama3.1:8b, 6.3GB) spilled 28% of its layers to CPU,
#   pulled in 816MB of swap, ran at 16 tok/s — and produced code that did
#   not compile anyway.
#
# Override for a one-off or an unusual host:
#   DOTFILES_CODING_MODEL=qwen3:8b make install-pi
#
# The qwen2.5-coder line is still the better *completion* model at any given
# size — if you want it for non-agentic use (in-editor completion, one-shot
# prompts with no tools), pull it explicitly with that override. Just do not
# point pi at it.

set -eu

if [ -n "${DOTFILES_CODING_MODEL:-}" ]; then
	echo "$DOTFILES_CODING_MODEL"
	exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILE=$("$SCRIPT_DIR/detect-ram-profile.sh")

if [ "$(uname -s)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ]; then
	# Apple silicon, unified memory (~75% wirable by the GPU).
	case "$PROFILE" in
		# ~18GB at q4 for the 30B/3.3B-active MoE — fits the ~24GB
		# wirable on a 32GB Mac, and only 3.3B params are active so it
		# stays fast. Ollama ships a dedicated qwen3-coder tool parser.
		# Untested here: no 32GB machine was available to run
		# verify-agent-model.sh against it.
		32gb) echo "qwen3-coder:30b" ;;
		# ~6.1GB resident, inside the ~12GB wirable budget on a 16GB
		# Mac with room for the OS and an editor. Verified to pass
		# verify-agent-model.sh, but only on the 8GB box this was
		# written on, where it spilled 24% to CPU — the capability is
		# measured, the fit at 16GB is still a prediction.
		16gb) echo "qwen3:8b" ;;
		# 3.9GB at 16K, 100% GPU on an 8GB M2, verified end to end.
		*) echo "qwen3:4b" ;;
	esac
elif [ "$(uname -s)" = "Darwin" ]; then
	# Intel Mac: CPU-bound at every size, so take the smallest tag that
	# still passes — see the Intel note above.
	echo "qwen3:4b"
else
	# Linux, typically with a discrete GPU whose VRAM is separate from
	# system RAM, so the same nominal RAM tier can carry a larger model.
	case "$PROFILE" in
		32gb) echo "qwen3-coder:30b" ;;
		16gb) echo "qwen3:8b" ;;
		# Was qwen2.5-coder:3b, then llama3.1:8b. Both failed
		# verify-agent-model.sh for different reasons.
		*) echo "qwen3:4b" ;;
	esac
fi
