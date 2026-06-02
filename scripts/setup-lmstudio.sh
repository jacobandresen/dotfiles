#!/usr/bin/env bash
# setup-lmstudio.sh — Download and configure Mistral 7B for LM Studio + pi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODEL_DIR="$HOME/.lmstudio/models/bartowski/Phi-3.5-mini-instruct-GGUF"
MODEL_FILE="$MODEL_DIR/Phi-3.5-mini-instruct-Q4_K_M.gguf"
HF_URL="https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf"

# ── Detect OS and set platform-specific values ────────────────────────────────
case "$(uname -s)" in
  Darwin)
    LMSTUDIO_SETTINGS="$HOME/Library/Application Support/LM Studio/settings.json"
    quit_lmstudio() { osascript -e 'quit app "LM Studio"' 2>/dev/null || true; }
    is_lmstudio_running() { pgrep -x "LM Studio" > /dev/null 2>&1; }
    ;;
  Linux)
    LMSTUDIO_SETTINGS="$HOME/.config/LM Studio/settings.json"
    quit_lmstudio() { pkill -x "lmstudio" 2>/dev/null || pkill -f "LM Studio" 2>/dev/null || true; }
    is_lmstudio_running() { pgrep -x "lmstudio" > /dev/null 2>&1 || pgrep -f "LM Studio" > /dev/null 2>&1; }
    ;;
  *)
    echo "Unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

# ── 1. Quit LM Studio if running ──────────────────────────────────────────────
if is_lmstudio_running; then
    echo "Quitting LM Studio..."
    quit_lmstudio
    sleep 3
fi

# ── 2. Disable model loading guardrails ───────────────────────────────────────
if [ -f "$LMSTUDIO_SETTINGS" ]; then
    echo "Disabling LM Studio model loading guardrails..."
    python3 - "$LMSTUDIO_SETTINGS" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    s = json.load(f)
s.setdefault('modelLoadingGuardrails', {})['mode'] = 'off'
with open(path, 'w') as f:
    json.dump(s, f, indent=2)
print("  ✓ Guardrails set to off")
PYEOF
else
    echo "  ⚠ LM Studio settings not found at: $LMSTUDIO_SETTINGS"
    echo "    Start LM Studio once to generate settings, then re-run."
fi

# ── 3. Download model ─────────────────────────────────────────────────────────
mkdir -p "$MODEL_DIR"
if [ -f "$MODEL_FILE" ]; then
    echo "  ✓ Model already present: $MODEL_FILE"
else
    echo "Downloading Phi-3.5 Mini Instruct Q4_K_M (~2.2 GB)..."
    curl -L --progress-bar "$HF_URL" -o "$MODEL_FILE"
    echo "  ✓ Download complete"
fi

# ── 4. Patch GGUF chat template ───────────────────────────────────────────────
echo "Checking GGUF chat template..."
python3 "$SCRIPT_DIR/patch-gguf-template.py" "$MODEL_FILE"

echo ""
echo "LM Studio setup complete."
echo "Start LM Studio and run 'pi' to use Phi-3.5 Mini."
