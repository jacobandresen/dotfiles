#!/usr/bin/env bash
# Check that Pi writes a C program that compiles and prints hello.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
	-h|--help)
		printf '%s\n' "Usage: $(basename "$0") [MODEL ...]"
		cat <<'HELP'
Verify selected or supplied models using a temporary Pi session.
Failed runs retain their artifacts for inspection.
HELP
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
		echo "  pulling $model..." >&2
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

exit $rc
