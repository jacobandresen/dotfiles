#!/usr/bin/env bash
# Configure host-local Pi settings using the selector or --use-loaded.
set -euo pipefail

DRY_RUN=false
VERBOSE=false
USE_LOADED=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            echo "Usage: $(basename "$0") [OPTIONS]"
            echo ""
            echo "Configure pi with this host's selected model (or --use-loaded)."
            echo ""
            echo "Options:"
            echo "  -h, --help     Show this help message and exit"
            echo "  -n, --dry-run  Show what would be done without making changes"
            echo "  -v, --verbose  Enable verbose output"
            echo "      --use-loaded  Use whatever model Ollama has resident,"
            echo "                    instead of this host's selected model"
            exit 0
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --use-loaded)
            USE_LOADED=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API="${OLLAMA_HOST:-http://127.0.0.1:11434}"
case "$API" in http*) ;; *) API="http://$API" ;; esac

echo "Host setup: configure pi with this host's selected model"
echo ""

if command -v ollama >/dev/null 2>&1; then
    echo "  Ollama is installed ($(ollama --version 2>/dev/null || echo 'unknown version'))"
else
    echo "  Ollama not found. Install it first:"
    echo "    macOS/Linux: curl -fsSL https://ollama.com/install.sh | sh"
    exit 1
fi

# Check if Ollama server is running
if ! curl -s -f --max-time 3 -o /dev/null "$API/v1/models" >/dev/null 2>&1; then
    echo "  Ollama server is not running. Starting it..."
    if $DRY_RUN; then
        echo "  [DRY-RUN] Would start Ollama server"
    else
        open -a Ollama 2>/dev/null || xdg-open ollama 2>/dev/null || ollama serve &
        sleep 5
        if ! curl -s -f --max-time 3 -o /dev/null "$API/v1/models" >/dev/null 2>&1; then
            echo "  Failed to start Ollama server. Start it manually, then re-run." >&2
            exit 1
        fi
        echo "  Ollama server started"
    fi
else
    echo "  Ollama server is running"
fi

echo ""

TMP_JSON="$(mktemp)"
trap 'rm -f "$TMP_JSON"' EXIT

SELECTED_MODEL="$("$SCRIPT_DIR/select-coding-model.sh")"

LOADED_MODEL=""
if curl -s --max-time 2 "$API/api/ps" -o "$TMP_JSON" 2>/dev/null && [ -s "$TMP_JSON" ]; then
    LOADED_MODEL=$(python3 -c "
import json
with open('$TMP_JSON') as f:
    models = json.load(f).get('models', [])
print(models[0]['name'] if models else '')
" 2>/dev/null || echo "")
fi

if $USE_LOADED; then
    if [ -z "$LOADED_MODEL" ]; then
        echo "  --use-loaded given, but Ollama has no model resident." >&2
        echo "    Load one first: ollama run <model>" >&2
        exit 1
    fi
    MODEL_NAME="$LOADED_MODEL"
    echo "  using the resident model: $MODEL_NAME (--use-loaded)"
    if [ "$MODEL_NAME" != "$SELECTED_MODEL" ]; then
        echo "  this host's selector picks $SELECTED_MODEL, not $MODEL_NAME."
        echo "    Check it with: ./scripts/verify-agent-model.sh $MODEL_NAME"
    fi
else
    MODEL_NAME="$SELECTED_MODEL"
    echo "  this host's model: $MODEL_NAME (from select-coding-model.sh)"
    if [ -n "$LOADED_MODEL" ] && [ "$LOADED_MODEL" != "$MODEL_NAME" ]; then
        echo "  Ollama currently has $LOADED_MODEL resident — ignoring it."
        echo "    Pass --use-loaded if you meant to point pi at that instead."
    fi
fi

PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
if $VERBOSE; then echo "Pi configuration directory: $PI_AGENT_DIR"; fi
args=(--agent-dir "$PI_AGENT_DIR" --model "$MODEL_NAME" --api "$API")
if $DRY_RUN; then args+=(--dry-run); fi
python3 "$SCRIPT_DIR/install-pi-config.py" "${args[@]}"
echo "Setup complete: pi configured to use $MODEL_NAME via Ollama"
