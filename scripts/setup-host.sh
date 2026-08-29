#!/usr/bin/env bash
# setup-host.sh — Point pi at whatever model Ollama currently has loaded
#
# No single model is pinned across hosts — GPUs differ per machine. This
# script:
#   - Confirms Ollama is installed and running
#   - Picks this host's model from select-coding-model.sh
#   - Points pi agent's settings.json / models.json at it
#
# It used to point pi at "whatever Ollama currently has resident", which is
# not safe: anything that loads a model changes what pi gets configured for.
# scripts/bench-model.sh does exactly that, and running it left llama3.1:8b
# resident — so the next setup-host run would silently repoint pi at a model
# verified NOT to produce compilable code. The selector is the authority now.
#
# --use-loaded restores the old behaviour for the case it was meant for:
# you ran `ollama run <model>` deliberately and want pi to follow. It warns
# when that disagrees with the selector, rather than switching in silence.
#
# Idempotent: safe to re-run after switching models or any hardware change.
set -euo pipefail

# --- Options --------------------------------------------------------------------
DRY_RUN=false
VERBOSE=false
USE_LOADED=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            echo "Usage: $(basename "$0") [OPTIONS]"
            echo ""
            echo "Point pi agent at whatever model Ollama currently has loaded."
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

# --- Helpers --------------------------------------------------------------------
run_cmd() {
    if $DRY_RUN; then
        echo "  [DRY-RUN] $*"
    else
        if $VERBOSE; then
            echo "  $ $*"
        fi
        eval "$@"
    fi
}

echo "============================================================================="
echo "Host setup: point pi at whatever model Ollama has loaded"
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

# --- 2. Detect the loaded model -----------------------------------------------
echo ""
echo "--- Detecting model ---"

TMP_JSON="$(mktemp)"
trap 'rm -f "$TMP_JSON"' EXIT

SELECTED_MODEL="$("$SCRIPT_DIR/select-coding-model.sh")"

LOADED_MODEL=""
if curl -s --max-time 2 http://localhost:11434/api/ps -o "$TMP_JSON" 2>/dev/null && [ -s "$TMP_JSON" ]; then
    LOADED_MODEL=$(python3 -c "
import json
with open('$TMP_JSON') as f:
    models = json.load(f).get('models', [])
print(models[0]['name'] if models else '')
" 2>/dev/null || echo "")
fi

if $USE_LOADED; then
    if [ -z "$LOADED_MODEL" ]; then
        echo "  ✗ --use-loaded given, but Ollama has no model resident." >&2
        echo "    Load one first: ollama run <model>" >&2
        exit 1
    fi
    MODEL_NAME="$LOADED_MODEL"
    echo "  ✓ using the resident model: $MODEL_NAME (--use-loaded)"
    if [ "$MODEL_NAME" != "$SELECTED_MODEL" ]; then
        echo "  ⚠ this host's selector picks $SELECTED_MODEL, not $MODEL_NAME."
        echo "    Check it with: ./scripts/verify-agent-model.sh $MODEL_NAME"
    fi
else
    MODEL_NAME="$SELECTED_MODEL"
    echo "  ✓ this host's model: $MODEL_NAME (from select-coding-model.sh)"
    if [ -n "$LOADED_MODEL" ] && [ "$LOADED_MODEL" != "$MODEL_NAME" ]; then
        echo "  ⚠ Ollama currently has $LOADED_MODEL resident — ignoring it."
        echo "    Pass --use-loaded if you meant to point pi at that instead."
    fi
fi

# --- 3. Configure pi agent ---------------------------------------------------------
echo ""
echo "--- pi agent ---"

PI_SETTINGS="$HOME/.pi/agent/settings.json"

# Ensure pi agent directory exists
mkdir -p "$HOME/.pi/agent" 2>/dev/null || true

# Ensure settings.json exists (symlink into repo)
if [ ! -f "$PI_SETTINGS" ]; then
    if [ -f "$SCRIPT_DIR/../pi/agent/settings.json" ]; then
        if $DRY_RUN; then
            echo "  [DRY-RUN] Would create symlink: $PI_SETTINGS -> $SCRIPT_DIR/../pi/agent/settings.json"
        else
            ln -sf "$SCRIPT_DIR/../pi/agent/settings.json" "$PI_SETTINGS"
            echo "  ✓ Created symlink: $PI_SETTINGS"
        fi
    fi
fi

# Set defaultModel to the detected model and defaultProvider to ollama
if command -v python3 >/dev/null 2>&1; then
    CURRENT_MODEL=$(python3 -c "import json; print(json.load(open('$PI_SETTINGS')).get('defaultModel', ''))" 2>/dev/null || echo "")
    CURRENT_PROVIDER=$(python3 -c "import json; print(json.load(open('$PI_SETTINGS')).get('defaultProvider', ''))" 2>/dev/null || echo "")
else
    CURRENT_MODEL=""
    CURRENT_PROVIDER=""
fi

if [ "$CURRENT_MODEL" = "$MODEL_NAME" ] && [ "$CURRENT_PROVIDER" = "ollama" ]; then
    echo "  ✓ pi agent already configured: $MODEL_NAME via Ollama"
else
    if $DRY_RUN; then
        echo "  [DRY-RUN] Would set defaultModel=$MODEL_NAME, defaultProvider=ollama"
    else
        python3 - "$PI_SETTINGS" "$MODEL_NAME" <<'PYEOF'
import json, sys
path, model_name = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        s = json.load(f)
except Exception as e:
    print(f"  x Failed to read {path}: {e}", file=sys.stderr)
    sys.exit(1)
s["defaultModel"] = model_name
s["defaultProvider"] = "ollama"
try:
    with open(path, "w") as f:
        json.dump(s, f, indent=2)
        f.write("\n")
    print(f"  ✓ pi agent configured: {model_name} via Ollama")
except IOError as e:
    print(f"  x Failed to write {path}: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
    fi
fi

# --- 4. Point models.json at the detected model for the ollama provider ---------
echo ""
echo "--- pi agent models.json ---"

PI_MODELS="$HOME/.pi/agent/models.json"

if [ -f "$PI_MODELS" ]; then
    if command -v python3 >/dev/null 2>&1; then
        HAS_MODEL=$(python3 - "$PI_MODELS" "$MODEL_NAME" <<'PYEOF' 2>/dev/null || echo "no"
import json, sys
path, model_name = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        cfg = json.load(f)
except Exception:
    sys.exit(1)
providers = cfg.get('providers', {})
ollama = providers.get('ollama', {})
models = ollama.get('models', [])
# Present is not enough: it also has to be the _launch entry, otherwise pi
# starts on whatever else in the catalog carries that flag.
found = any(m.get('id') == model_name and m.get('_launch') for m in models)
sys.exit(0 if found else 1)
PYEOF
)

        if [ "$HAS_MODEL" = "no" ]; then
            if $DRY_RUN; then
                echo "  [DRY-RUN] Would set $MODEL_NAME in models.json"
            else
                python3 - "$PI_MODELS" "$MODEL_NAME" <<'PYEOF'
import json, sys
path, model_name = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        cfg = json.load(f)
except Exception as e:
    print(f"  x Failed to read {path}: {e}", file=sys.stderr)
    sys.exit(1)

providers = cfg.setdefault("providers", {})
ollama = providers.setdefault("ollama", {})

# Add the detected model and mark it as the launch default -- but keep every
# other entry. ~/.pi is a symlink into this repo, so replacing the catalog
# wholesale rewrote the committed models.json and dropped the per-model
# contextWindow/maxTokens and the provider `compat` block with it. That is
# not cosmetic: without them pi falls back to its own defaults and the model
# silently runs in a different context window than the Ollama profile
# provides.
models = ollama.setdefault("models", [])
for m in models:
    m.pop("_launch", None)

entry = next((m for m in models if m.get("id") == model_name), None)
if entry is None:
    entry = {
        "id": model_name,
        "input": ["text"],
        "name": f"{model_name} (via Ollama)",
        "contextWindow": 16384,
        "maxTokens": 4096,
    }
    models.insert(0, entry)
entry["_launch"] = True

ollama["api"] = "openai-completions"
ollama["apiKey"] = "not-needed"
ollama["baseUrl"] = "http://127.0.0.1:11434/v1"
ollama.setdefault("compat", {
    "supportsDeveloperRole": False,
    "supportsReasoningEffort": False,
})

try:
    with open(path, "w") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")
    print(f"  ✓ models.json updated with {model_name} for ollama")
except IOError as e:
    print(f"  x Failed to write {path}: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
            fi
        else
            echo "  ✓ $MODEL_NAME already the launch model in models.json"
        fi
    fi
else
    echo "  ⚠ $PI_MODELS not found"
fi

echo ""
echo "============================================================================="
echo "Setup complete: pi agent configured to use $MODEL_NAME via Ollama"
echo "============================================================================="
