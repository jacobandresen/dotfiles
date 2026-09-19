#!/usr/bin/env bash
# verify-agent-model.sh — Does this model actually drive pi end to end?
#
# The one test that matters for this repo: point pi at a model, ask it for a
# hello world in C, and check that a *compilable, runnable* binary lands on
# disk. Everything short of that has produced false positives here:
#
#   `ollama show` says `tools`        -> qwen2.5-coder declares it and never
#                                        emits a call
#   a one-tool curl probe returns
#   tool_calls                        -> llama3.2:3b passes it, then reverts
#                                        to text mimicry under pi's real
#                                        prompt
#   pi calls write/bash               -> llama3.1:8b gets this far and still
#                                        fails: it writes the literal two
#                                        characters \n into the file and
#                                        drops #include <stdio.h>, so the
#                                        transcript looks like a success and
#                                        the C does not compile
#
# So the check is the artifact, not the transcript. A model passes only if
# hello.c compiles with -Werror-ish strictness and the binary prints hello.
#
# Usage:
#   ./verify-agent-model.sh                 # this host's selected model
#   ./verify-agent-model.sh qwen3:4b ...    # specific tags
#
# Each run is a fresh temp dir and an ephemeral pi session, so nothing here
# touches the real project or session history.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
	-h|--help)
		sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
esac

if [ $# -gt 0 ]; then
	MODELS=("$@")
else
	MODELS=("$("$SCRIPT_DIR/select-coding-model.sh")")
fi

PROMPT='Create hello.c in the current directory: a C program that prints Hello, World! Then compile it with `cc hello.c -o hello` and run ./hello. Use your tools to do this; do not just show me the code.'

CC=${CC:-cc}
rc=0

printf '\n%-22s %-8s %-10s %-9s %s\n' MODEL WROTE COMPILES RUNS VERDICT
printf '%s\n' "----------------------------------------------------------------------"

for model in "${MODELS[@]}"; do
	if ! ollama list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$model"; then
		echo "  ↓ pulling $model..." >&2
		ollama pull "$model" >/dev/null 2>&1 || {
			printf '%-22s %-8s %-10s %-9s %s\n' "$model" - - - "PULL FAILED"
			rc=1
			continue
		}
	fi

	work="$(mktemp -d)"
	log="$work/pi.log"

	# --no-session keeps this out of session history; -nc drops AGENTS.md so
	# every model is judged on pi's own prompt, not on repo instructions.
	(cd "$work" && pi -p --provider ollama --model "$model" \
		--no-session -nc "$PROMPT" >"$log" 2>&1)

	wrote=no; compiles=no; runs=no
	src="$(ls "$work"/*.c 2>/dev/null | head -1)"
	if [ -n "$src" ] && [ -s "$src" ]; then
		wrote=yes
		if "$CC" -std=c11 -Wall "$src" -o "$work/verify.bin" >"$work/cc.log" 2>&1; then
			compiles=yes
			out="$("$work/verify.bin" 2>/dev/null)"
			case "$out" in *[Hh]ello*) runs=yes ;; esac
		fi
	fi

	if [ "$runs" = yes ]; then
		verdict="PASS"
	else
		verdict="FAIL"
		rc=1
	fi
	printf '%-22s %-8s %-10s %-9s %s\n' "$model" "$wrote" "$compiles" "$runs" "$verdict"

	if [ "$verdict" = FAIL ]; then
		echo "    artifacts: $work" >&2
	else
		rm -rf "$work"
	fi
done

echo
echo "A PASS means pi wrote C that compiled and printed hello — the only signal"
echo "that separates a working agent model from one that fakes the transcript."
exit $rc
