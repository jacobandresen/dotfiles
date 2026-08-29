#!/usr/bin/env bash
# setup-model.sh — Pull and load this host's coding model into Ollama
#
# Ensures the model is pulled and resident in memory so it's the one
# setup-host.sh picks up (it points pi at whatever Ollama currently has
# loaded).
#
# The model is no longer hardcoded: it comes from select-coding-model.sh,
# which requires a model verified to drive pi end to end and then sizes it
# for this machine's RAM and, on macOS, its memory architecture. A hardcoded
# tag was wrong on both ends — too large to load on an 8GB Mac, too small to
# bother with on a 32GB workstation — and it silently disagreed with the
# model `make install-pi` had already pulled.
#
# Override with an argument or the same env var the selector honours:
#   ./setup-model.sh qwen3:8b
#   DOTFILES_CODING_MODEL=qwen3:8b ./setup-model.sh
#
# If you override, run scripts/verify-agent-model.sh on the tag first — it
# is the only check that catches all three failure modes. A model that
# cannot drive pi loads fine here and then fails *silently*: it either
# prints its tool calls as chat text (qwen2.5-coder, at every size) or calls
# the tools with mangled arguments and writes C that does not compile
# (llama3.1:8b). Both look like success in the transcript.
#
# Idempotent: safe to re-run; a no-op if already pulled and loaded. Note this
# only holds if nothing else on the box is concurrently loading a different
# model (e.g. another agent hitting the same Ollama server) - re-run right
# before you need it if in doubt.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_NAME=""

# --- Options --------------------------------------------------------------------
DRY_RUN=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            echo "Usage: $(basename "$0") [OPTIONS] [MODEL]"
            echo ""
            echo "Pull and load this host's coding model into Ollama."
            echo "Defaults to $("$SCRIPT_DIR/select-coding-model.sh"), from select-coding-model.sh."
            echo ""
            echo "Arguments:"
            echo "  MODEL          Ollama tag to use instead of the default"
            echo ""
            echo "Options:"
            echo "  -h, --help     Show this help message and exit"
            echo "  -n, --dry-run  Show what would be done without making changes"
            echo "  -v, --verbose  Enable verbose output"
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
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            MODEL_NAME="$1"
            shift
            ;;
    esac
done

# Fall back to the host-appropriate model when none was given explicitly.
if [ -z "$MODEL_NAME" ]; then
    MODEL_NAME="$("$SCRIPT_DIR/select-coding-model.sh")"
fi

echo "============================================================================="
echo "Model setup: $MODEL_NAME via Ollama"
echo "============================================================================="
echo ""

# --- 1. Check/install Ollama -------------------------------------------------------
echo "--- Ollama ---"
if command -v ollama >/dev/null 2>&1; then
    echo "  ✓ Ollama is installed ($(ollama --version 2>/dev/null || echo 'unknown version'))"
else
    echo "  ✗ Ollama not found. Install it first:"
    echo "    macOS/Linux: curl -fsSL https://ollama.com/install.sh | sh"
    exit 1
fi

# Check if Ollama server is running
if ! curl -s -f -o /dev/null http://localhost:11434/v1/models >/dev/null 2>&1; then
    echo "  ⚠ Ollama server is not running. Starting it..."
    if $DRY_RUN; then
        echo "  [DRY-RUN] Would start Ollama server"
    else
        open -a Ollama 2>/dev/null || xdg-open ollama 2>/dev/null || ollama serve &
        sleep 5
        if ! curl -s -f -o /dev/null http://localhost:11434/v1/models >/dev/null 2>&1; then
            echo "  ✗ Failed to start Ollama server. Start it manually, then re-run." >&2
            exit 1
        fi
        echo "  ✓ Ollama server started"
    fi
else
    echo "  ✓ Ollama server is running"
fi

# --- 2. Pull the model --------------------------------------------------------------
echo ""
echo "--- Pulling $MODEL_NAME ---"

if ollama list 2>/dev/null | awk '{print $1}' | grep -qx "$MODEL_NAME"; then
    echo "  ✓ $MODEL_NAME is already pulled"
else
    if $DRY_RUN; then
        echo "  [DRY-RUN] Would run: ollama pull $MODEL_NAME"
    else
        echo "  Pulling $MODEL_NAME..."
        if ! ollama pull "$MODEL_NAME"; then
            echo "  ✗ Failed to pull $MODEL_NAME" >&2
            exit 1
        fi
        echo "  ✓ $MODEL_NAME pulled successfully"
    fi
fi

# --- 3. Load the model into memory ---------------------------------------------------
echo ""
echo "--- Loading $MODEL_NAME ---"

TMP_JSON="$(mktemp)"
trap 'rm -f "$TMP_JSON"' EXIT

ALREADY_LOADED=false
if curl -s --max-time 2 http://localhost:11434/api/ps -o "$TMP_JSON" 2>/dev/null && [ -s "$TMP_JSON" ]; then
    if python3 -c "
import json, sys
with open('$TMP_JSON') as f:
    models = json.load(f).get('models', [])
sys.exit(0 if any(m.get('name') == '$MODEL_NAME' for m in models) else 1)
" 2>/dev/null; then
        ALREADY_LOADED=true
    fi
fi

if $ALREADY_LOADED; then
    echo "  ✓ $MODEL_NAME is already loaded"
elif $DRY_RUN; then
    echo "  [DRY-RUN] Would load $MODEL_NAME into memory"
else
    echo "  Loading $MODEL_NAME (first load can take a while)..."
    # An empty/no prompt can send some models into an unbounded "thinking"
    # loop instead of loading and returning - send a trivial real prompt
    # instead, and ask Ollama to keep it resident well past its 5m default.
    if ! echo "hi" | ollama run "$MODEL_NAME" --keepalive 24h >/dev/null; then
        echo "  ✗ Failed to load $MODEL_NAME" >&2
        exit 1
    fi
    echo "  ✓ $MODEL_NAME loaded into memory"
fi

echo ""
echo "============================================================================="
echo "Setup complete: $MODEL_NAME pulled and loaded in Ollama"
echo "============================================================================="
