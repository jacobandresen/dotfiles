#!/usr/bin/env bash
# setup-host.sh — Point pi at whatever model Ollama currently has loaded
#
# No single model is pinned across hosts — GPUs differ per machine, and the
# loaded model can change any time via `ollama run <model>`. This script:
#   - Confirms Ollama is installed and running
#   - Detects whichever model Ollama currently has resident in memory
#     (falling back to the most recently pulled model if nothing is loaded)
#   - Points pi agent's settings.json / models.json at that model
#
# Idempotent: safe to re-run after switching models or any hardware change.
set -euo pipefail

# --- Options --------------------------------------------------------------------
DRY_RUN=false
VERBOSE=false

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

MODEL_NAME=""
if curl -s --max-time 2 http://localhost:11434/api/ps -o "$TMP_JSON" 2>/dev/null && [ -s "$TMP_JSON" ]; then
    MODEL_NAME=$(python3 -c "
import json
with open('$TMP_JSON') as f:
    models = json.load(f).get('models', [])
print(models[0]['name'] if models else '')
" 2>/dev/null || echo "")
fi

if [ -n "$MODEL_NAME" ]; then
    echo "  ✓ $MODEL_NAME is currently loaded in Ollama"
else
    echo "  ⚠ nothing currently loaded — falling back to the most recently pulled model"
    if curl -s --max-time 2 http://localhost:11434/api/tags -o "$TMP_JSON" 2>/dev/null && [ -s "$TMP_JSON" ]; then
        MODEL_NAME=$(python3 -c "
import json
with open('$TMP_JSON') as f:
    models = json.load(f).get('models', [])
models.sort(key=lambda m: m.get('modified_at', ''), reverse=True)
print(models[0]['name'] if models else '')
" 2>/dev/null || echo "")
    fi
    if [ -n "$MODEL_NAME" ]; then
        echo "  ✓ using $MODEL_NAME (most recently pulled)"
    fi
fi

if [ -z "$MODEL_NAME" ]; then
    echo "  ✗ No models found. Pull one first: ollama pull <model>" >&2
    exit 1
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
found = any(m.get('id') == model_name for m in models)
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

# The catalog holds exactly one model: whatever Ollama currently has loaded.
ollama["models"] = [{
    "_launch": True,
    "id": model_name,
    "input": ["text"],
    "name": f"{model_name} (via Ollama)"
}]

ollama["api"] = "openai-completions"
ollama["apiKey"] = "not-needed"
ollama["baseUrl"] = "http://127.0.0.1:11434/v1"

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
            echo "  ✓ $MODEL_NAME already in models.json for ollama"
        fi
    fi
else
    echo "  ⚠ $PI_MODELS not found"
fi

echo ""
echo "============================================================================="
echo "Setup complete: pi agent configured to use $MODEL_NAME via Ollama"
echo "============================================================================="
