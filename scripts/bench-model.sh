#!/usr/bin/env bash
# bench-model.sh — Measure whether a model actually fits this machine.
#
# select-coding-model.sh picks a model from RAM and memory architecture, but
# those tiers are a prediction. This checks the prediction on real hardware.
#
# This measures FIT ONLY. It deliberately does not try to judge whether a
# model can drive pi — that question defeated two cheap proxies here:
#
#   `ollama show` capabilities   qwen2.5-coder advertises `tools` at every
#                                size and never emits a call
#   a one-tool curl probe        wrong in BOTH directions. llama3.1:8b
#                                returns a clean tool_call and then writes C
#                                that does not compile (false pass), while
#                                qwen3:4b spends the probe's token budget
#                                reasoning and returns finish_reason=length
#                                with tool_calls=null (false fail) — on the
#                                very model this repo ships.
#
# A column that is wrong in both directions is worse than no column, so it
# was removed. scripts/verify-agent-model.sh answers that question properly,
# by compiling and running what pi actually wrote.
#
# The number that matters is not tokens/sec, it is the PROCESSOR split from
# `ollama ps`. Anything short of "100% GPU" means the model didn't fit the
# GPU's wirable budget and Ollama spilled layers to CPU — on Apple silicon
# that budget is ~75% of unified RAM (sysctl iogpu.wired_limit_mb, 0 =
# default), shared with the OS and everything else you have open. Swap growth
# is the other tell: it doesn't show up in a throughput average, but it is
# what makes the machine feel broken while an agent is running.
#
# Usage:
#   ./bench-model.sh                     # this host's selected model
#   ./bench-model.sh qwen3:8b            # a specific model
#   ./bench-model.sh qwen3:4b qwen3:8b   # compare tiers
#
# Models are pulled if missing, but never removed — a comparison run can
# leave several GB on disk. `ollama rm <model>` to reclaim it.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API="${OLLAMA_HOST:-http://127.0.0.1:11434}"
case "$API" in http*) ;; *) API="http://$API" ;; esac

NUM_PREDICT=160

case "${1:-}" in
	-h|--help)
		sed -n '2,37p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
esac

if ! curl -sf --max-time 3 "$API/api/version" >/dev/null 2>&1; then
	echo "✗ Ollama is not responding on $API" >&2
	echo "  On macOS a fresh install needs its first-run setup completed once:" >&2
	echo "    open -a Ollama" >&2
	exit 1
fi

MODELS=("$@")
if [ ${#MODELS[@]} -eq 0 ]; then
	MODELS=("$("$SCRIPT_DIR/select-coding-model.sh")")
	echo "No model given — benchmarking this host's selection: ${MODELS[0]}"
fi

PROMPTS=(
	"Write a Python function that merges two sorted lists into one sorted list. Code only."
	"Explain what a race condition is in two sentences."
	"Write a bash one-liner that finds the 10 largest files under a directory."
)

swap_used_mb() { sysctl -n vm.swapusage 2>/dev/null | awk '{print $6}' | tr -d 'M' || echo 0; }

printf '\n%-22s %8s %8s %8s %8s %10s  %s\n' MODEL GEN_TPS PROMPT_TPS LOAD_S SIZE SWAP_DELTA PROCESSOR
printf '%s\n' "-------------------------------------------------------------------------------------------"

for model in "${MODELS[@]}"; do
	if ! ollama list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$model"; then
		echo "  ↓ pulling $model..." >&2
		ollama pull "$model" >/dev/null 2>&1 || { echo "  ✗ pull failed: $model" >&2; continue; }
	fi

	# Force a cold load so load_duration means something.
	curl -s "$API/api/generate" -d "{\"model\":\"$model\",\"keep_alive\":0}" >/dev/null 2>&1
	sleep 3

	swap_before=$(swap_used_mb)

	results=""
	for p in "${PROMPTS[@]}"; do
		body=$(python3 -c 'import json,sys; print(json.dumps({"model":sys.argv[1],"prompt":sys.argv[2],"stream":False,"options":{"num_predict":int(sys.argv[3])}}))' "$model" "$p" "$NUM_PREDICT")
		resp=$(curl -s --max-time 900 "$API/api/generate" -d "$body")
		line=$(python3 - "$resp" <<'PY'
import json,sys
try: d=json.loads(sys.argv[1])
except Exception: sys.exit(1)
if "error" in d:
    print("ERR", d["error"][:60], file=sys.stderr); sys.exit(1)
ns=1e9
ped=d.get("prompt_eval_duration",0)/ns; ed=d.get("eval_duration",0)/ns
print(f'{d.get("eval_count",0)/ed if ed else 0:.2f} '
      f'{d.get("prompt_eval_count",0)/ped if ped else 0:.1f} '
      f'{d.get("load_duration",0)/ns:.2f}')
PY
) || { echo "  ✗ generation failed: $model" >&2; continue 2; }
		results+="$line"$'\n'
	done

	swap_after=$(swap_used_mb)
	ps_line=$(ollama ps 2>/dev/null | awk -v m="$model" '$1==m{print $3$4" "$5" "$6}')
	size=$(echo "$ps_line" | awk '{print $1}')
	proc=$(echo "$ps_line" | cut -d' ' -f2-)

	# NB: the program itself arrives on stdin via this heredoc, so the samples
	# have to come through argv — a pipe here would be silently discarded.
	python3 - "$model" "$swap_before" "$swap_after" "${size:-?}" "${proc:-?}" "$results" <<'PY'
import sys
rows=[l.split() for l in sys.argv[6].split("\n") if l.strip()]
model,sb,sa,size,proc=sys.argv[1:6]
if not rows:
    print(f"{model:<22}  (no samples collected)"); sys.exit(0)
gen=sum(float(r[0]) for r in rows)/len(rows)
pro=sum(float(r[1]) for r in rows)/len(rows)
load=max(float(r[2]) for r in rows)
delta=float(sa)-float(sb)
flag="" if delta<=1 else f"  <-- swapped +{delta:.0f}MB"
print(f"{model:<22} {gen:8.1f} {pro:8.1f} {load:8.2f} {size:>8} {delta:9.0f}M  {proc}{flag}")
PY
done

echo
echo "This says nothing about whether the model can drive pi — run"
echo "./verify-agent-model.sh for that. A model can bench perfectly here and"
echo "still be useless as an agent."
echo
echo "PROCESSOR must read 100% GPU. Any CPU share means the model did not fit"
echo "and layers spilled — expect roughly half the throughput and swap growth."
