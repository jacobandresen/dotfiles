#!/usr/bin/env bash
# Load a model and configure Pi to use it. KEEPALIVE defaults to 4h.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API="${OLLAMA_HOST:-http://127.0.0.1:11434}"
case "$API" in http*) ;; *) API="http://$API" ;; esac

KEEPALIVE="${KEEPALIVE:-4h}"
MODEL="${1:-$("$SCRIPT_DIR/select-coding-model.sh")}"

# Normalize bare model names to :latest before comparing.
ollama_has() {
	case "$1" in *:*) _t="$1" ;; *) _t="$1:latest" ;; esac
	ollama list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$_t"
}

echo "Pointing the local stack at: $MODEL"

if ! curl -sf --max-time 3 "$API/api/version" >/dev/null 2>&1; then
	echo "  Ollama not responding at $API — starting it..."
	open -a Ollama 2>/dev/null || (ollama serve >/dev/null 2>&1 &)
	for _ in 1 2 3 4 5 6 7 8 9 10; do
		curl -sf --max-time 2 "$API/api/version" >/dev/null 2>&1 && break
		sleep 1
	done
fi
curl -sf --max-time 3 "$API/api/version" >/dev/null 2>&1 || {
	echo "  Ollama unreachable at $API" >&2; exit 1; }
echo "  Ollama responding at $API"

if ollama_has "$MODEL"; then
	echo "  $MODEL is present"
else
	echo "  pulling $MODEL..."
	ollama pull "$MODEL"
fi

echo "  loading $MODEL (keep-alive $KEEPALIVE)..."
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
    print("Error:", d["error"], file=sys.stderr); sys.exit(1)
PY
echo "  $MODEL loaded"

echo ""
# --use-loaded: we just loaded this model deliberately, so pi should follow
# it rather than the selector's pick (setup-host.sh defaults to the selector).
"$SCRIPT_DIR/setup-host.sh" --use-loaded
