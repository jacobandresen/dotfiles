#!/usr/bin/env bash
# setup-lmstudio.sh — Download and configure models for LM Studio + pi.
# Default model: Bonsai-27B (Prism ML) — ultra-low-quant, pre-downloaded,
# only ~3.6 GB on disk, safe to run on any GPU.
# Also supports Mistral AI models (Codestral, Mistral, Mixtral) and Qwen
# models via --model.
#
# Model selection priority:
#   1. Bonsai-27B - default
#   2. Mistral AI models (Codestral, Mistral, Mixtral) - opt-in via --model
#   3. Qwen models - fallback for compatibility
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

Supported Models:
  - bonsai-27b                  (default, ~3.6 GB, pre-downloaded/symlinked)
  - mistral-7b-instruct-v0.3    (~4.4 GB Q4_K_M)
  - mistral-7b-instruct-v0.2    (~4.4 GB Q4_K_M)
  - mistral-7b-instruct-v0.1    (~4.4 GB Q4_K_M)
  - mixtral-8x7b-instruct-v0.1  (~24 GB Q4_K_M)
  - codestral-22b-v0.1          (~14 GB Q4_K_M, requires 11+ GB VRAM)
  - codestral-latest            (latest, ~14 GB Q4_K_M, requires 11+ GB VRAM)
  - qwen2.5-coder-7b-instruct   (fallback, ~4.4 GB)
  - qwen2.5-coder-3b-instruct   (fallback, ~3.8 GB, lightweight)

Examples:
  $(basename "$0")                              # Auto-detect and download Bonsai-27B
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
EXPLICIT_PROVIDER=""

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

# Set default model to Bonsai-27B (pre-downloaded, ultra-low-quant, only 3.6 GB
# on disk — safe for any GPU). Use --model to opt into Mistral/Codestral/Qwen.
if [ -n "$EXPLICIT_MODEL" ]; then
    MODEL_ID="$EXPLICIT_MODEL"
else
    MODEL_ID="bonsai-27b"
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
        mistral-7b-instruct-v0.3|mistralai/mistral-7b-instruct-v0.3)
            # Mistral AI's official v0.3; LM Studio serves it under the
            # mistralai/ alias, on-disk under lmstudio-community/.
            echo "mistralai/mistral-7b-instruct-v0.3 Q4_K_M"
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
        bonsai-27b|bonsai|prism-ml/bonsai-27b)
            # Bonsai-27B by Prism ML — ultra-low-quant 27B, only 3.6 GB on disk.
            # Model is pre-downloaded and symlinked into .lmstudio/models/.
            echo "prism-ml/Bonsai-27B-gguf/bonsai-27b.gguf PRELOADED"
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

# Validate quant value (skip for pre-downloaded models)
if [[ "$QUANT" != "PRELOADED" ]]; then
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
fi

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
    print(f"  ✗ Failed to parse {path}: {e}", file=sys.stderr)
    sys.exit(1)
except FileNotFoundError:
    print(f"  ✗ File not found: {path}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"  ✗ Error reading {path}: {e}", file=sys.stderr)
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
    print(f"  ✗ Failed to write {path}: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
    fi
else
    echo "  ⚠ LM Studio settings not found at: $LMSTUDIO_SETTINGS"
    echo "    Start LM Studio once to generate settings, then re-run."
fi

# ── 3. Download model ─────────────────────────────────────────────────────────
# Prefer the LM Studio CLI (`lms get`): it resolves the hub alias to the correct
# GGUF, is resumable + size-verified, and — crucially for the official Mistral —
# registers the served id the pin expects (`mistralai/mistral-7b-instruct-v0.3`,
# whose GGUF lives on-disk under lmstudio-community/). The mistralai/ HF repo
# hosts only safetensors, so a raw curl of a .gguf 404s; `lms get` handles it.
# Falls back to a resumable, Content-Length-verified curl for models given as an
# explicit HF repo (e.g. TheBloke mirrors) when `lms` is unavailable.

# GNU (Linux) and BSD (macOS) stat take different flags; try both.
file_size() { stat -c %s "$1" 2>/dev/null || stat -f %z "$1" 2>/dev/null || echo 0; }

# For pre-downloaded models (e.g. Bonsai-27B), skip download entirely.
if [[ "$QUANT" == "PRELOADED" ]]; then
    BONSAI_FILE="$HOME/.lmstudio/models/$MODEL_REPO"
    if [ -f "$BONSAI_FILE" ]; then
        echo "  ✓ Model already on disk: $BONSAI_FILE"
    else
        echo "  ✗ Expected model file not found: $BONSAI_FILE" >&2
        echo "    Ensure the symlink exists: ~/.lmstudio/models/prism-ml/Bonsai-27B-gguf/bonsai-27b.gguf" >&2
        exit 1
    fi
elif $DRY_RUN; then
    echo "  [DRY-RUN] Would download: $MODEL_ID ($QUANT) via 'lms get $MODEL_REPO@$QUANT'"
elif command -v lms >/dev/null 2>&1; then
    echo "Downloading $MODEL_ID ($QUANT) via lms get…"
    lms get "$MODEL_REPO@$QUANT" -y || lms get "$MODEL_REPO" -y || \
        { echo "  ✗ 'lms get $MODEL_REPO' failed" >&2; exit 1; }
    echo "  ✓ Model present via lms"
else
    # Fallback: resumable, size-verified curl against the computed HF GGUF URL.
    PARTIAL_FILE="$MODEL_FILE"
    mkdir -p "$MODEL_DIR" || { echo "  ✗ Failed to create directory: $MODEL_DIR" >&2; exit 1; }
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
        echo "  ✓ Model present ($LOCAL_SIZE bytes); skipped size check (server unreachable)"
    else
        echo "Downloading $MODEL_ID $QUANT from $HF_URL…"
        PARTIAL_FILE="$MODEL_FILE.partial"
        curl -L -C - --retry 3 --retry-delay 2 --progress-bar "$HF_URL" -o "$PARTIAL_FILE" || \
            { echo "  ✗ Download failed" >&2; exit 1; }
        mv "$PARTIAL_FILE" "$MODEL_FILE" || { echo "  ✗ Failed to move downloaded file" >&2; exit 1; }
        LOCAL_SIZE="$(file_size "$MODEL_FILE")"
        if [ -n "$EXPECTED_SIZE" ] && [ "$LOCAL_SIZE" != "$EXPECTED_SIZE" ]; then
            rm -f "$MODEL_FILE"; PARTIAL_FILE=""
            echo "  ✗ Download incomplete: got $LOCAL_SIZE bytes, expected $EXPECTED_SIZE." >&2
            exit 1
        fi
        echo "  ✓ Download complete ($LOCAL_SIZE bytes)"
    fi
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
if [[ "$QUANT" != "PRELOADED" ]] && ! $DRY_RUN && [ -d "$MODEL_DIR" ]; then
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
# Mistral's v0.3 GGUF template rejects the system role ("Only user and assistant
# roles are supported!") → HTTP 400 on every mu/pi call until patched. The patch
# is idempotent and MUST re-run after any re-download. `lms get` stores the file
# under lmstudio-community/…, not the computed $MODEL_FILE, so resolve the real
# path by recursive glob and patch every match.
echo "Checking GGUF chat template..."
if $DRY_RUN; then
    echo "  [DRY-RUN] Would patch GGUF chat template for: $MODEL_ID"
else
    GGUFS=()
    [ -f "$MODEL_FILE" ] && GGUFS+=("$MODEL_FILE")
    if [ ${#GGUFS[@]} -eq 0 ] && [[ "$MODEL_ID" == *mistral* && "$MODEL_ID" == *v0.3* ]]; then
        while IFS= read -r g; do GGUFS+=("$g"); done < <(
            find "$HOME/.lmstudio/models" -iname '*mistral*7b*instruct*v0.3*.gguf' 2>/dev/null)
    fi
    if [ ${#GGUFS[@]} -eq 0 ]; then
        echo "  ⚠ Model GGUF not found, skipping template patch" >&2
    else
        for g in "${GGUFS[@]}"; do
            python3 "$SCRIPT_DIR/patch-gguf-template.py" "$g" || \
                { echo "  ✗ Failed to patch GGUF template: $g" >&2; exit 1; }
        done
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
