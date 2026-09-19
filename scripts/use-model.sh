#!/usr/bin/env bash
# use-model.sh — point the whole local stack at one model.
#
# pi, nvim's CodeCompanion adapter and the mu agent all resolve the same way:
# "whichever model Ollama currently has loaded" (`/api/ps`), falling back to
# whatever is pulled. So switching the stack is two steps — load the model,
# then re-run setup-host.sh to rewrite pi's settings.json/models.json — and
# this does both.
#
#   ./use-model.sh              # this host's selected model (see select-coding-model.sh)
#   ./use-model.sh bonsai-27b   # the 1-bit 27B build from install-bonsai.sh
#
# Loads with a long keep-alive so the model stays resident across a work
# session; the profile's own OLLAMA_KEEP_ALIVE takes over once it expires.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API="${OLLAMA_HOST:-http://127.0.0.1:11434}"
case "$API" in http*) ;; *) API="http://$API" ;; esac

KEEPALIVE="${KEEPALIVE:-4h}"
MODEL="${1:-$("$SCRIPT_DIR/select-coding-model.sh")}"

# `ollama list` always prints a tag, so normalise a bare name before comparing.
ollama_has() {
	case "$1" in *:*) _t="$1" ;; *) _t="$1:latest" ;; esac
	ollama list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$_t"
}

echo "============================================================================="
echo "Pointing the local stack at: $MODEL"
echo "============================================================================="

if ! curl -sf --max-time 3 "$API/api/version" >/dev/null 2>&1; then
	echo "  ⚠ Ollama not responding at $API — starting it..."
	open -a Ollama 2>/dev/null || (ollama serve >/dev/null 2>&1 &)
	for _ in 1 2 3 4 5 6 7 8 9 10; do
		curl -sf --max-time 2 "$API/api/version" >/dev/null 2>&1 && break
		sleep 1
	done
fi
curl -sf --max-time 3 "$API/api/version" >/dev/null 2>&1 || {
	echo "  ✗ Ollama unreachable at $API" >&2; exit 1; }
echo "  ✓ Ollama responding at $API"

if ollama_has "$MODEL"; then
	echo "  ✓ $MODEL is present"
elif [ "$MODEL" = "bonsai-27b" ]; then
	# Bonsai isn't a registry pull — it's built locally from the HF weights.
	echo "  → $MODEL not built yet; running install-bonsai.sh"
	"$SCRIPT_DIR/install-bonsai.sh"
else
	echo "  ↓ pulling $MODEL..."
	ollama pull "$MODEL"
fi

echo "  ⏳ loading $MODEL (keep-alive $KEEPALIVE)..."
python3 - "$API" "$MODEL" "$KEEPALIVE" <<'PY'
import json, sys, urllib.request
api, model, keep = sys.argv[1:4]
body = json.dumps({"model": model, "prompt": "hi", "stream": False,
                   "think": False, "keep_alive": keep}).encode()
req = urllib.request.Request(f"{api}/api/generate", data=body,
                             headers={"Content-Type": "application/json"})
with urllib.request.urlopen(req, timeout=900) as r:
    d = json.load(r)
if d.get("error"):
    print("  ✗", d["error"], file=sys.stderr); sys.exit(1)
PY
echo "  ✓ $MODEL loaded"

echo ""
"$SCRIPT_DIR/setup-host.sh"
