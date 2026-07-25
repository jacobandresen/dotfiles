#!/usr/bin/env bash
# setup-host.sh — Setup Ollama with gemma4:12b for all platforms
#
# Unified configuration: gemma4:12b is the single model used across all hosts.
# This script ensures:
#   - Ollama is installed and running
#   - gemma4:12b model is pulled
#   - pi agent is configured to use gemma4:12b via Ollama
#
# Idempotent: safe to re-run after any change.
set -euo pipefail

# --- Options --------------------------------------------------------------------
DRY_RUN=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            echo "Usage: $(basename "$0") [OPTIONS]"
            echo ""
            echo "Setup Ollama with gemma4:12b model."
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
echo "Host setup: gemma4:12b via Ollama (unified across all platforms)"
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

# --- 2. Pull gemma4:12b model ------------------------------------------------------
echo ""
echo "--- gemma4:12b model ---"

MODEL_NAME="gemma4:12b"

# Check if model is already pulled
if ollama list 2>/dev/null | grep -q "$MODEL_NAME"; then
    echo "  ✓ $MODEL_NAME is already pulled"
else
    echo "  Pulling $MODEL_NAME..."
    if $DRY_RUN; then
        echo "  [DRY-RUN] Would run: ollama pull $MODEL_NAME"
    else
        if ! ollama pull "$MODEL_NAME"; then
            echo "  ✗ Failed to pull $MODEL_NAME" >&2
            exit 1
        fi
        echo "  ✓ $MODEL_NAME pulled successfully"
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

# Set defaultModel to gemma4:12b and defaultProvider to ollama
if command -v python3 >/dev/null 2>&1; then
    CURRENT_MODEL=$(python3 -c "import json; print(json.load(open('$PI_SETTINGS')).get('defaultModel', ''))" 2>/dev/null || echo "")
    CURRENT_PROVIDER=$(python3 -c "import json; print(json.load(open('$PI_SETTINGS')).get('defaultProvider', ''))" 2>/dev/null || echo "")
else
    CURRENT_MODEL=""
    CURRENT_PROVIDER=""
fi

if [ "$CURRENT_MODEL" = "gemma4:12b" ] && [ "$CURRENT_PROVIDER" = "ollama" ]; then
    echo "  ✓ pi agent already configured: gemma4:12b via Ollama"
else
    if $DRY_RUN; then
        echo "  [DRY-RUN] Would set defaultModel=gemma4:12b, defaultProvider=ollama"
    else
        python3 - "$PI_SETTINGS" <<'PYEOF'
import json, sys
path = sys.argv[1]
try:
    with open(path) as f:
        s = json.load(f)
except Exception as e:
    print(f"  x Failed to read {path}: {e}", file=sys.stderr)
    sys.exit(1)
s["defaultModel"] = "gemma4:12b"
s["defaultProvider"] = "ollama"
try:
    with open(path, "w") as f:
        json.dump(s, f, indent=2)
        f.write("\n")
    print("  ✓ pi agent configured: gemma4:12b via Ollama")
except IOError as e:
    print(f"  x Failed to write {path}: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
    fi
fi

# --- 4. Ensure models.json has gemma4:12b for ollama provider -------------------
echo ""
echo "--- pi agent models.json ---"

PI_MODELS="$HOME/.pi/agent/models.json"

if [ -f "$PI_MODELS" ]; then
    if command -v python3 >/dev/null 2>&1; then
        HAS_MODEL=$(python3 -c "
import json, sys
try:
    with open('$PI_MODELS') as f:
        cfg = json.load(f)
    providers = cfg.get('providers', {})
    ollama = providers.get('ollama', {})
    models = ollama.get('models', [])
    for m in models:
        if m.get('id') == 'gemma4:12b':
            sys.exit(0)
    sys.exit(1)
except:
    sys.exit(1)
" 2>/dev/null || echo "no")

        if [ "$HAS_MODEL" = "no" ]; then
            if $DRY_RUN; then
                echo "  [DRY-RUN] Would add gemma4:12b to models.json"
            else
                python3 - "$PI_MODELS" <<'PYEOF'
import json, sys
path = sys.argv[1]
try:
    with open(path) as f:
        cfg = json.load(f)
except Exception as e:
    print(f"  x Failed to read {path}: {e}", file=sys.stderr)
    sys.exit(1)

providers = cfg.setdefault("providers", {})
ollama = providers.setdefault("ollama", {})
models = ollama.setdefault("models", [])

for m in models:
    m.pop("_launch", None)

models = [m for m in models if m.get("id") == "gemma4:12b"]
if not any(m.get("id") == "gemma4:12b" for m in models):
    models.append({
        "_launch": True,
        "id": "gemma4:12b",
        "input": ["text"],
        "name": "Gemma 4 12B (via Ollama)"
    })

ollama["api"] = "openai-completions"
ollama["apiKey"] = "not-needed"
ollama["baseUrl"] = "http://127.0.0.1:11434/v1"

try:
    with open(path, "w") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")
    print("  ✓ models.json updated with gemma4:12b for ollama")
except IOError as e:
    print(f"  x Failed to write {path}: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
            fi
        else
            echo "  ✓ gemma4:12b already in models.json for ollama"
        fi
    fi
else
    echo "  ⚠ $PI_MODELS not found"
fi

echo ""
echo "============================================================================="
echo "Setup complete: gemma4:12b via Ollama configured for all platforms"
echo "============================================================================="
