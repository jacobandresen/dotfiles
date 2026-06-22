#!/usr/bin/env bash
# setup-lmstudio.sh — Download and configure Qwen2.5-Coder-7B-Instruct for LM Studio + pi.
# The quant is host-aware: pick the largest that loads fully on-GPU on this machine.
#   • Q3_K_L (~3.8 GB) — default. The quant chosen by a 10-problem dojo board on an
#     8 GB M2 (best score, 7/10) and the largest that runs under that Mac's ~4.1 GB
#     GPU compute-buffer ceiling. The 7B Q4_K_M (~4.4 GB) won't load there; 8B
#     models (>4.3 GB) hit a GPU "Compute error".
#   • Q4_K_M (~4.4 GB) — used on a discrete NVIDIA card with ≥6 GB VRAM (e.g. the
#     GTX 1660 SUPER, 6 GB), which has room for the weights + KV cache + compute
#     buffer that the Mac's unified memory doesn't. Scores better than Q3_K_L and
#     is the largest quant lmstudio-community publishes for this repo.
# pi addresses the model by a quant-agnostic id ("qwen2.5-coder-7b-instruct"), so
# LM Studio serves whichever GGUF this script drops in the folder — no pi changes.
# See mu/docs/quantization-and-the-stack.md for the full reasoning.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Pick the model quant for this host ────────────────────────────────────────
# Default to the conservative Q3_K_L; bump to Q4_K_M only on a discrete NVIDIA
# GPU with enough VRAM (≥6 GB) to hold the larger weights plus runtime buffers.
# A pre-set $QUANT (e.g. from setup-host.sh, which does one shared detection pass)
# wins, so the nvidia-smi probe isn't duplicated across scripts.
nvidia_vram_mib() {
    command -v nvidia-smi > /dev/null 2>&1 || return 1
    nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null \
      | head -n1 | tr -dc '0-9'
}

if [ -n "${QUANT:-}" ]; then
    echo "Using caller-provided quant: $QUANT."
else
    QUANT="Q3_K_L"
    if [ "$(uname -s)" = "Linux" ]; then
        VRAM_MIB="$(nvidia_vram_mib || true)"
        if [ -n "${VRAM_MIB:-}" ] && [ "$VRAM_MIB" -ge 6000 ] 2>/dev/null; then
            QUANT="Q4_K_M"
            echo "Detected discrete NVIDIA GPU with ${VRAM_MIB} MiB VRAM → using $QUANT."
        fi
    fi
fi

MODEL_DIR="$HOME/.lmstudio/models/lmstudio-community/Qwen2.5-Coder-7B-Instruct-GGUF"
MODEL_FILE="$MODEL_DIR/Qwen2.5-Coder-7B-Instruct-$QUANT.gguf"
HF_URL="https://huggingface.co/lmstudio-community/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/Qwen2.5-Coder-7B-Instruct-$QUANT.gguf"

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

# ── 2. Tune LM Studio settings (guardrails off, no bundled auto-load) ─────────
if [ -f "$LMSTUDIO_SETTINGS" ]; then
    echo "Tuning LM Studio settings for a small/shared GPU..."
    python3 - "$LMSTUDIO_SETTINGS" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    s = json.load(f)
# Let pi JIT-load the coder model even on a tight VRAM budget.
s.setdefault('modelLoadingGuardrails', {})['mode'] = 'off'
# Don't auto-load the bundled model on startup. pi JIT-loads the coder model
# it needs, so the bundled one is just wasted memory — harmless on a big Mac,
# but on a small discrete GPU (e.g. a 6 GB card) it squats on VRAM and starves
# pi's load: "unable to allocate CUDA0 buffer".
s['autoLoadBundledLLM'] = False
with open(path, 'w') as f:
    json.dump(s, f, indent=2)
print("  ✓ Guardrails off, bundled-model auto-load disabled")
PYEOF
else
    echo "  ⚠ LM Studio settings not found at: $LMSTUDIO_SETTINGS"
    echo "    Start LM Studio once to generate settings, then re-run."
fi

# ── 3. Download model (size-verified, resumable) ──────────────────────────────
# A bare `[ -f ]` check can't tell a truncated 1.9 GB partial download from the
# real 2.1 GB file, so it silently keeps a corrupt model ("tensor data is not
# within the file bounds, model is corrupted or incomplete") and never repairs
# it on re-run. Compare against the server's Content-Length and resume instead.
mkdir -p "$MODEL_DIR"

# GNU (Linux) and BSD (macOS) stat take different flags; try both.
file_size() { stat -c %s "$1" 2>/dev/null || stat -f %z "$1" 2>/dev/null || echo 0; }

# Ask the server for the real size. Only trust it on a clean 2xx (`-f` makes
# curl exit non-zero otherwise) — gating on the exit status via `if` both keeps
# a transient/404 HEAD from tripping `set -e` and avoids mistaking an error
# page's Content-Length for the model's. The character classes match both
# casings ("Content-Length" on HTTP/1.1, "content-length" on HTTP/2) without
# awk's IGNORECASE, a GNU-awk-only extension absent on macOS's BSD awk. An empty
# EXPECTED_SIZE just falls back to the old download-if-missing behaviour below.
if HEADERS="$(curl -fsIL "$HF_URL" 2>/dev/null)"; then
    EXPECTED_SIZE="$(printf '%s\n' "$HEADERS" \
      | awk '/^[Cc]ontent-[Ll]ength:/{cl=$2} END{gsub(/\r/,"",cl); print cl}')"
else
    EXPECTED_SIZE=""
fi
LOCAL_SIZE="$(file_size "$MODEL_FILE")"

if [ -n "$EXPECTED_SIZE" ] && [ "$LOCAL_SIZE" = "$EXPECTED_SIZE" ]; then
    echo "  ✓ Model already present and complete ($LOCAL_SIZE bytes)"
elif [ -z "$EXPECTED_SIZE" ] && [ "$LOCAL_SIZE" != "0" ]; then
    # Couldn't reach the server to verify (offline?), but a file is already
    # here — trust it rather than running `curl -C -` against a complete file
    # (which can 416 and, under `set -e`, abort setup).
    echo "  ✓ Model present ($LOCAL_SIZE bytes); skipped size check (server unreachable)"
else
    if [ "$LOCAL_SIZE" != "0" ]; then
        echo "  ⚠ Model is $LOCAL_SIZE bytes, expected ${EXPECTED_SIZE:-unknown} — resuming download..."
    else
        echo "Downloading Qwen2.5-Coder-7B-Instruct $QUANT..."
    fi
    curl -L -C - --retry 3 --retry-delay 2 --progress-bar "$HF_URL" -o "$MODEL_FILE"
    LOCAL_SIZE="$(file_size "$MODEL_FILE")"
    if [ -n "$EXPECTED_SIZE" ] && [ "$LOCAL_SIZE" != "$EXPECTED_SIZE" ]; then
        echo "  ✗ Download incomplete: got $LOCAL_SIZE bytes, expected $EXPECTED_SIZE." >&2
        echo "    Re-run 'make setup-lmstudio' to resume." >&2
        exit 1
    fi
    echo "  ✓ Download complete ($LOCAL_SIZE bytes)"
fi

# ── 4. Remove other quants of this model ──────────────────────────────────────
# pi addresses the model by the bare id "qwen2.5-coder-7b-instruct". LM Studio
# resolves that to a single GGUF only when one quant of the model sits in the
# folder; with two present (e.g. after switching hosts or bumping the quant), the
# bare id becomes ambiguous and pi's load fails ("Failed to load model"). Drop
# every sibling quant except the one we just verified — and its .bak left by the
# template patcher — so the id stays unambiguous (and we reclaim the disk).
for stale in "$MODEL_DIR"/Qwen2.5-Coder-7B-Instruct-*.gguf; do
    [ -e "$stale" ] || continue            # no glob match → literal pattern, skip
    [ "$stale" = "$MODEL_FILE" ] && continue
    echo "  ✓ Removing other quant: $(basename "$stale")"
    rm -f "$stale" "$stale.bak"
done

# ── 5. Patch GGUF chat template ───────────────────────────────────────────────
echo "Checking GGUF chat template..."
python3 "$SCRIPT_DIR/patch-gguf-template.py" "$MODEL_FILE"

echo ""
echo "LM Studio setup complete."
echo "Start LM Studio and run 'pi' to use Qwen2.5-Coder-7B ($QUANT)."
