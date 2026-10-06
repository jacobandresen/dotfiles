#!/usr/bin/env bash
# Load a model and configure Pi to use it. KEEPALIVE defaults to 4h.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ollama-common.sh"
API="${OLLAMA_HOST:-http://127.0.0.1:11434}"
case "$API" in http*) ;; *) API="http://$API" ;; esac

KEEPALIVE="${KEEPALIVE:-4h}"
SKIP_IF_UNAVAILABLE=false
CONFIGURE_PI=true
DRY_RUN=false
MODEL=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--skip-if-unavailable) SKIP_IF_UNAVAILABLE=true ;;
		--ollama-only) CONFIGURE_PI=false ;;
		-n|--dry-run) DRY_RUN=true ;;
		--keepalive)
			shift
			if [[ $# -eq 0 ]]; then echo "--keepalive requires a value" >&2; exit 1; fi
			KEEPALIVE="$1"
			;;
		--keepalive=*) KEEPALIVE="${1#*=}" ;;
		-v|--verbose) ;;
		-h|--help)
			echo "Usage: $(basename "$0") [OPTIONS] [MODEL]"
			echo "  --ollama-only          pull/load without configuring Pi"
			echo "  --skip-if-unavailable  skip missing or unready Ollama"
			echo "  -n, --dry-run          show actions without changing anything"
			echo "  --keepalive VALUE      model retention time (default: $KEEPALIVE)"
			exit 0
			;;
		-*) echo "Unknown option: $1" >&2; exit 1 ;;
		*)
			if [ -n "$MODEL" ]; then echo "Only one model may be specified" >&2; exit 1; fi
			MODEL="$1"
			;;
	esac
	shift
done
MODEL="${MODEL:-$("$SCRIPT_DIR/select-coding-model.sh")}"

if $CONFIGURE_PI; then
	echo "Pointing the local stack at: $MODEL"
else
	echo "Setting up Ollama model: $MODEL"
fi

if ! command -v ollama >/dev/null 2>&1; then
	if $SKIP_IF_UNAVAILABLE; then
		echo "  Ollama not found — skipping model setup (run 'make deps' first)."
		exit 0
	fi
	echo "  Ollama not found — install it first." >&2
	exit 1
fi

if $DRY_RUN; then
	if ! curl -sf --max-time 3 "$API/api/version" >/dev/null 2>&1; then
		echo "  [DRY-RUN] Would start Ollama at $API"
		echo "  [DRY-RUN] Would ensure $MODEL is pulled and loaded (keep-alive $KEEPALIVE)"
	else
		if ollama_has_model "$MODEL"; then
			echo "  $MODEL is present"
		else
			echo "  [DRY-RUN] Would pull $MODEL"
		fi
		echo "  [DRY-RUN] Would load $MODEL (keep-alive $KEEPALIVE)"
	fi
	if $CONFIGURE_PI; then echo "  [DRY-RUN] Would configure Pi to use $MODEL"; fi
	exit 0
fi

if ! curl -sf --max-time 3 "$API/api/version" >/dev/null 2>&1; then
	echo "  Ollama not responding at $API — starting it..."
	open -a Ollama 2>/dev/null || (ollama serve >/dev/null 2>&1 &)
	for _ in 1 2 3 4 5 6 7 8 9 10; do
		curl -sf --max-time 2 "$API/api/version" >/dev/null 2>&1 && break
		sleep 1
	done
fi
curl -sf --max-time 3 "$API/api/version" >/dev/null 2>&1 || {
	if $SKIP_IF_UNAVAILABLE; then
		echo "  Ollama is not responding at $API — skipping model setup." >&2
		if [ "$(uname -s)" = Darwin ]; then
			echo "    Finish Ollama.app's first-run setup, then rerun 'make install-pi'." >&2
		else
			echo "    Start Ollama, then rerun 'make install-pi'." >&2
		fi
		exit 0
	fi
	echo "  Ollama unreachable at $API" >&2; exit 1; }
echo "  Ollama responding at $API"

if ollama_has_model "$MODEL"; then
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
if $CONFIGURE_PI; then
	"$SCRIPT_DIR/setup-host.sh" --use-loaded
fi
