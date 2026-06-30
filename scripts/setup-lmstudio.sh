#!/usr/bin/env bash
# setup-lmstudio.sh — Download and configure models for LM Studio + pi.
# Primary focus: Mistral AI models (Codestral, Mistral, Mixtral).
# Supports Qwen models as fallback.
#
# The quant/model is host-aware: pick the largest that loads fully on-GPU on this
# machine. Default is Codestral-22B with Q4_K_M quant (~14 GB) for capable GPUs,
# falling back to smaller variants for constrained hardware.
#
# Model selection priority:
#   1. Mistral AI models (Codestral, Mistral, Mixtral) - preferred
#   2. Qwen models - fallback for compatibility
#
# See: https://mistral.ai/, https://huggingface.co/mistralai
# For quantization details: https://github.com/mistralai/mistral-src
set -euo pipefail

# --- Error handling helpers --------------------------------------------------

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Download and configure Mistral AI models for LM Studio.

Options:
  -h, --help             Show this help message and exit
  -n, --dry-run          Show what would be done without making changes
  -v, --verbose          Enable verbose output
  --model MODEL          Specify model to download (e.g., codestral-22b-v0.1, mistral-7b)
  --quant Q              Override quant selection (e.g., Q4_K_M, Q3_K_L)
  --provider PROVIDER    Specify provider (lmstudio, mistral, openrouter)

Supported Mistral AI Models:
  - codestral-22b-v0.1    (default, ~14 GB Q4_K_M)
  - codestral-latest      (latest Codestral)
  - mistral-7b-instruct-v0.2
  - mistral-7b-instruct-v0.1
  - mixtral-8x7b-instruct-v0.1
  - qwen2.5-coder-7b-instruct (fallback)
  - qwen2.5-coder-3b-instruct (fallback, lightweight)

Examples:
  $(basename "$0")                              # Auto-detect and download Codestral
  $(basename "$0") --model codestral-22b-v0.1  # Download specific model
  $(basename "$0") --model mistral-7b-instruct-v0.2
  $(basename "$0") --quant Q4_K_M                # Force specific quant
  $(basename "$0") --dry-run                    # Preview actions only
EOF
}

DRY_RUN=false
VERBOSE=false
EXPLICIT_QUANT=""
EXPLICIT_MODEL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
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
        --model)
            EXPLICIT_MODEL="$2"
            shift 2
            ;;
        --quant)
            EXPLICIT_QUANT="$2"
            shift 2
            ;;
        --provider)
            EXPLICIT_PROVIDER="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

# Validate dependencies
validate_dependencies() {
    local missing=()
    
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    command -v python3 >/dev/null 2>&1 || missing+=("python3")
    command -v mkdir >/dev/null 2>&1 || missing+=("mkdir")
    command -v stat >/dev/null 2>&1 || missing+=("stat")
    command -v awk >/dev/null 2>&1 || missing+=("awk")
    command -v tr >/dev/null 2>&1 || missing+=("tr")
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo "  ✗ Missing dependencies: ${missing[*]}" >&2
        echo "  Install with:" >&2
        echo "    Ubuntu/Debian: sudo apt-get install curl python3 coreutils awk" >&2
        echo "    Arch:          sudo pacman -S curl python coreutils awk" >&2
        echo "    macOS:        brew install curl python gawk" >&2
        exit 1
    fi
}

# Cleanup partial downloads on failure
cleanup() {
    if [ -n "${PARTIAL_FILE:-}" ] && [ -f "$PARTIAL_FILE" ]; then
        echo "  ⚠ Cleaning up partial download: $PARTIAL_FILE" >&2
        rm -f "$PARTIAL_FILE"
    fi
}

trap cleanup ERR EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Model configuration -------------------------------------------------------

# Set default model to Codestral (Mistral AI's flagship coding model)
if [ -n "$EXPLICIT_MODEL" ]; then
    MODEL_ID="$EXPLICIT_MODEL"
else
    MODEL_ID="codestral-22b-v0.1"
fi

# Set default provider
if [ -n "$EXPLICIT_PROVIDER" ]; then
    PROVIDER="$EXPLICIT_PROVIDER"
else
    PROVIDER="lmstudio"
fi

# Map model IDs to their HuggingFace repos and default quants
get_model_info() {
    local model_id="$1"
    case "$model_id" in
        codestral-22b-v0.1|codestral-latest)
            echo "mistralai/Codestral-22B-v0.1-GGUF Q4_K_M"
            ;;
        mistral-7b-instruct-v0.2)
            echo "mistralai/Mistral-7B-Instruct-v0.2-GGUF Q4_K_M"
            ;;
        mistral-7b-instruct-v0.1)
            echo "TheBloke/Mistral-7B-Instruct-v0.1-GGUF Q4_K_M"
            ;;
        mixtral-8x7b-instruct-v0.1)
            echo "TheBloke/Mixtral-8x7B-Instruct-v0.1-GGUF Q4_K_M"
            ;;
        qwen2.5-coder-7b-instruct)
            echo "lmstudio-community/Qwen2.5-Coder-7B-Instruct-GGUF Q3_K_L"
            ;;
        qwen2.5-coder-3b-instruct)
            echo "lmstudio-community/Qwen2.5-Coder-3B-Instruct-GGUF Q3_K_L"
            ;;
        *)
            echo "$model_id Q4_K_M"
            ;;
    esac
}

MODEL_INFO=$(get_model_info "$MODEL_ID")
MODEL_REPO=$(echo "$MODEL_INFO" | awk '{print $1}')
DEFAULT_QUANT=$(echo "$MODEL_INFO" | awk '{print $2}')

# Use explicit quant if provided via --quant flag, otherwise use default
if [ -n "$EXPLICIT_QUANT" ]; then
    QUANT="$EXPLICIT_QUANT"
else
    QUANT="$DEFAULT_QUANT"
fi

# Validate provider
case "$PROVIDER" in
    lmstudio|mistral|openrouter)
        ;;
    *)
        echo "  ✗ Invalid provider: $PROVIDER. Use lmstudio, mistral, or openrouter" >&2
        exit 1
        ;;
esac

# Validate required tools
validate_dependencies

# ── Pick the quant for this host (Mistral models use Q4_K_M by default) ─────────
# For Mistral models, adjust quant based on available VRAM.
# Codestral-22B needs ~14 GB for Q4_K_M, so we may need to fall back to Q3_K_L
# on machines with less VRAM.

# GPU detection helper
nvidia_vram_mib() {
    command -v nvidia-smi > /dev/null 2>&1 || return 1
    nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null \
      | head -n1 | tr -dc '0-9'
}

# For Codestral and large models, check VRAM and adjust quant if needed
if [[ "$MODEL_ID" == "codestral-22b-v0.1" || "$MODEL_ID" == "codestral-latest" ]] && [ "$(uname -s)" = "Linux" ]; then
    VRAM_MIB="$(nvidia_vram_mib || true)"
    if [ -n "${VRAM_MIB:-}" ] && [ "$VRAM_MIB" -lt 16000 ] 2>/dev/null; then
        # Less than 16 GB VRAM - use Q3_K_L for Codestral
        if [ -z "$EXPLICIT_QUANT" ]; then
            QUANT="Q3_K_L"
            echo "  ⚠ GPU has ${VRAM_MIB} MiB VRAM (< 16 GB) → using Q3_K_L for Codestral"
        fi
    elif [ -n "${VRAM_MIB:-}" ]; then
        echo "  ✓ GPU has ${VRAM_MIB} MiB VRAM (≥ 16 GB) → using $QUANT for Codestral"
    fi
fi

# For explicit quant flag, override the default
if [ -n "$EXPLICIT_QUANT" ]; then
    QUANT="$EXPLICIT_QUANT"
    echo "Using explicit quant from --quant flag: $QUANT."
fi

# Validate quant value
case "$QUANT" in
    Q2_K|Q3_K_L|Q4_K_M|Q5_K_M|Q6_K|Q8_0)
        # Valid quants
        ;;
    *)
        echo "  ✗ Invalid quant: $QUANT" >&2
        echo "  Valid options: Q2_K, Q3_K_L, Q4_K_M, Q5_K_M, Q6_K, Q8_0" >&2
        exit 1
        ;;
esac

# Dry-run mode
if $DRY_RUN; then
    echo "  [DRY-RUN] Model: $MODEL_ID"
    echo "  [DRY-RUN] Quant: $QUANT"
    echo "  [DRY-RUN] Provider: $PROVIDER"
    echo "  [DRY-RUN] HF Repo: $MODEL_REPO"
    echo "  [DRY-RUN] Would proceed with LM Studio setup"
fi

# Determine model directory and file based on model repo
# For Mistral models: mistralai/Codestral-22B-v0.1-GGUF
# For Qwen models: lmstudio-community/Qwen2.5-Coder-7B-Instruct-GGUF
MODEL_BASENAME=$(basename "$MODEL_REPO" .GGUF)
MODEL_DIR="$HOME/.lmstudio/models/$(dirname "$MODEL_REPO")"
MODEL_FILENAME="${MODEL_BASENAME}-${QUANT}.gguf"
MODEL_FILE="$MODEL_DIR/$MODEL_FILENAME"
HF_URL="https://huggingface.co/$MODEL_REPO/resolve/main/$MODEL_FILENAME"

# For Qwen models, use the old directory structure for backward compatibility
if [[ "$MODEL_REPO" == *"Qwen2.5-Coder"* ]]; then
    MODEL_DIR="$HOME/.lmstudio/models/lmstudio-community/Qwen2.5-Coder-7B-Instruct-GGUF"
    MODEL_FILE="$MODEL_DIR/Qwen2.5-Coder-7B-Instruct-$QUANT.gguf"
    HF_URL="https://huggingface.co/lmstudio-community/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/Qwen2.5-Coder-7B-Instruct-$QUANT.gguf"
fi

echo "Model configuration:"
echo "  Model: $MODEL_ID"
echo "  Repo: $MODEL_REPO"
echo "  Quant: $QUANT"
echo "  Directory: $MODEL_DIR"
echo "  File: $MODEL_FILE"

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
    echo "  ✗ Unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

# ── 1. Quit LM Studio if running ──────────────────────────────────────────────
if is_lmstudio_running; then
    echo "Quitting LM Studio..."
    if ! $DRY_RUN; then
        quit_lmstudio
        sleep 3
        if is_lmstudio_running; then
            echo "  ⚠ LM Studio is still running. Please close it manually." >&2
        fi
    else
        echo "  [DRY-RUN] Would quit LM Studio"
    fi
fi

# ── 2. Tune LM Studio settings (guardrails off, no bundled auto-load) ─────────
if [ -f "$LMSTUDIO_SETTINGS" ]; then
    echo "Tuning LM Studio settings for Mistral AI models..."
    if $DRY_RUN; then
        echo "  [DRY-RUN] Would update LM Studio settings:"
        echo "    - modelLoadingGuardrails.mode = 'off'"
        echo "    - autoLoadBundledLLM = false"
    else
        python3 - "$LMSTUDIO_SETTINGS" <<'PYEOF'
import json, sys
path = sys.argv[1]
try:
    with open(path) as f:
        s = json.load(f)
except json.JSONDecodeError as e:
    print(f"  ✗ Failed to parse {path}: {e}" >&2)
    sys.exit(1)
except FileNotFoundError:
    print(f"  ✗ File not found: {path}" >&2)
    sys.exit(1)
except Exception as e:
    print(f"  ✗ Error reading {path}: {e}" >&2)
    sys.exit(1)

# Let pi JIT-load the coder model even on a tight VRAM budget.
s.setdefault('modelLoadingGuardrails', {})['mode'] = 'off'
# Don't auto-load the bundled model on startup. pi JIT-loads the coder model
# it needs, so the bundled one is just wasted memory — harmless on a big Mac,
# but on a small discrete GPU (e.g. a 6 GB card) it squats on VRAM and starves
# pi's load: "unable to allocate CUDA0 buffer".
s['autoLoadBundledLLM'] = False
try:
    with open(path, 'w') as f:
        json.dump(s, f, indent=2)
        f.write('\n')
    print("  ✓ Guardrails off, bundled-model auto-load disabled")
except IOError as e:
    print(f"  ✗ Failed to write {path}: {e}" >&2)
    sys.exit(1)
PYEOF
    fi
else
    echo "  ⚠ LM Studio settings not found at: $LMSTUDIO_SETTINGS"
    echo "    Start LM Studio once to generate settings, then re-run."
fi

# ── 3. Download model (size-verified, resumable) ──────────────────────────────
# A bare `[ -f ]` check can't tell a truncated 1.9 GB partial download from the
# real 2.1 GB file, so it silently keeps a corrupt model ("tensor data is not
# within the file bounds, model is corrupted or incomplete") and never repairs
# it on re-run. Compare against the server's Content-Length and resume instead.

MODEL_DIR="$HOME/.lmstudio/models/lmstudio-community/Qwen2.5-Coder-7B-Instruct-GGUF"
MODEL_FILE="$MODEL_DIR/Qwen2.5-Coder-7B-Instruct-$QUANT.gguf"
HF_URL="https://huggingface.co/lmstudio-community/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/Qwen2.5-Coder-7B-Instruct-$QUANT.gguf"

# Track partial file for cleanup
PARTIAL_FILE="$MODEL_FILE"

if ! $DRY_RUN; then
    mkdir -p "$MODEL_DIR" || { echo "  ✗ Failed to create directory: $MODEL_DIR" >&2; exit 1; }
fi

# GNU (Linux) and BSD (macOS) stat take different flags; try both.
file_size() { stat -c %s "$1" 2>/dev/null || stat -f %z "$1" 2>/dev/null || echo 0; }

# Ask the server for the real size. Only trust it on a clean 2xx (`-f` makes
# curl exit non-zero otherwise) — gating on the exit status via `if` both keeps
# a transient/404 HEAD from tripping `set -e` and avoids mistaking an error
# page's Content-Length for the model's. The character classes match both
# casings ("Content-Length" on HTTP/1.1, "content-length" on HTTP/2) without
# awk's IGNORECASE, a GNU-awk-only extension absent on macOS's BSD awk. An empty
# EXPECTED_SIZE just falls back to the old download-if-missing behaviour below.
if $DRY_RUN; then
    echo "  [DRY-RUN] Would check model at: $MODEL_FILE"
    echo "  [DRY-RUN] Would download from: $HF_URL"
else
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
        # Track partial file for cleanup on error
        PARTIAL_FILE="$MODEL_FILE.partial"
        curl -L -C - --retry 3 --retry-delay 2 --progress-bar "$HF_URL" -o "$PARTIAL_FILE" || \
            { echo "  ✗ Download failed" >&2; exit 1; }
        mv "$PARTIAL_FILE" "$MODEL_FILE" || { echo "  ✗ Failed to move downloaded file" >&2; exit 1; }
        LOCAL_SIZE="$(file_size "$MODEL_FILE")"
        if [ -n "$EXPECTED_SIZE" ] && [ "$LOCAL_SIZE" != "$EXPECTED_SIZE" ]; then
            # Clean up incomplete download
            rm -f "$MODEL_FILE"
            PARTIAL_FILE=""
            echo "  ✗ Download incomplete: got $LOCAL_SIZE bytes, expected $EXPECTED_SIZE." >&2
            echo "    Re-run 'make setup-lmstudio' to resume." >&2
            exit 1
        fi
        echo "  ✓ Download complete ($LOCAL_SIZE bytes)"
    fi
    # Clear partial file tracker after successful download
    PARTIAL_FILE=""
fi

# ── 4. Remove other quants of this model ──────────────────────────────────────
# pi addresses the model by its bare id (e.g., "codestral-22b-v0.1", 
# "qwen2.5-coder-7b-instruct"). LM Studio resolves that to a single GGUF only
# when one quant of the model sits in the folder; with two present (e.g. after 
# switching hosts or bumping the quant), the bare id becomes ambiguous and pi's 
# load fails ("Failed to load model"). Drop every sibling quant except the one we 
# just verified — and its .bak left by the template patcher — so the id stays 
# unambiguous (and we reclaim the disk).
if ! $DRY_RUN && [ -d "$MODEL_DIR" ]; then
    # Build glob pattern based on model filename
    MODEL_BASE=$(basename "$MODEL_FILENAME" | sed "s|-$QUANT.gguf$||")
    for stale in "$MODEL_DIR"/${MODEL_BASE}-*.gguf; do
        [ -e "$stale" ] || continue            # no glob match → literal pattern, skip
        [ "$stale" = "$MODEL_FILE" ] && continue
        echo "  ✓ Removing other quant: $(basename "$stale")"
        rm -f "$stale" "$stale.bak"
    done
elif $DRY_RUN; then
    echo "  [DRY-RUN] Would remove other quant files from: $MODEL_DIR"
fi

# ── 5. Patch GGUF chat template ───────────────────────────────────────────────
echo "Checking GGUF chat template..."
if $DRY_RUN; then
    echo "  [DRY-RUN] Would patch GGUF chat template for: $MODEL_FILE"
else
    if [ ! -f "$MODEL_FILE" ]; then
        echo "  ⚠ Model file not found, skipping template patch" >&2
    else
        python3 "$SCRIPT_DIR/patch-gguf-template.py" "$MODEL_FILE" || \
            { echo "  ✗ Failed to patch GGUF template" >&2; exit 1; }
    fi
fi

if $DRY_RUN; then
    echo ""
    echo "[DRY-RUN] LM Studio setup would be complete. No changes were made."
    echo "  To execute: run without --dry-run flag"
else
    echo ""
    echo "LM Studio setup complete."
    echo "Start LM Studio and run 'pi' to use $MODEL_ID ($QUANT)."
    echo ""
    if [[ "$MODEL_ID" == "codestral"* ]]; then
        echo "  🎯 Primary model: Codestral (Mistral AI's flagship coding model)"
    fi
fi
