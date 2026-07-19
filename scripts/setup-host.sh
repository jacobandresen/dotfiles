#!/usr/bin/env bash
# setup-host.sh — Tune the local LLM stack (LM Studio + pi) to this machine's
# hardware for Mistral AI and Qwen models. One GPU-detection pass picks a
# profile, then it:
#   • LM Studio — downloads/keeps the right model with appropriate quant for
#                 the VRAM (Codestral-22B, Mistral-7B, Mixtral-8x7B, Qwen, Bonsai-27B)
#   • pi        — sets defaultModel in ~/.pi/agent/settings.json to match the
#                 hardware profile. EXCEPTION: skips this entirely if defaultModel
#                 is already a Bonsai-27B id — that means the host opted into the
#                 Bonsai-27B default (see README.md § pi agent; loaded through the
#                 same LM Studio server as the models below, just a different model
#                 id), so leave it alone rather than overwriting it with a
#                 Mistral/Codestral/Qwen pick.
#
# (mu, the other consumer of this LM Studio server, tunes itself — see
# `make setup-host` in the mu repo, which writes ~/.zshrc.mu independently.)
#
# ~/.pi/agent/* are symlinks into this repo, shared by every host. The committed
# configs stay host-agnostic: pi's defaultModel is host-managed — each machine's
# run sets its own model, so that field shouldn't be committed.
#
# Idempotent: re-run after a GPU change and it rewrites the profile.
set -euo pipefail

# --- Error handling helpers --------------------------------------------------

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Tune LM Studio and pi agent to the current machine's GPU.

Options:
  -h, --help     Show this help message and exit
  -n, --dry-run  Show what would be done without making changes
  -v, --verbose  Enable verbose output

Examples:
  $(basename "$0")              # Run with actual changes
  $(basename "$0") --dry-run    # Preview changes only
EOF
}

DRY_RUN=false
VERBOSE=false

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
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

# Ensure we can detect GPU info
detect_gpu_info() {
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        echo "  ⚠ nvidia-smi not found (Linux only; macOS uses unified memory)" >&2
        return 1
    fi
    return 0
}

# Cleanup on error - remove any partial state
trap 'echo "\n✗ Setup failed. Check errors above." >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Detect GPU VRAM (NVIDIA only; Macs use unified memory, handled as default) ─
nvidia_vram_mib() {
    command -v nvidia-smi > /dev/null 2>&1 || return 1
    nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null \
      | head -n1 | tr -dc '0-9'
}
nvidia_name() {
    nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1
}

VRAM_MIB=""
GPU_DESC="none detected (using unified-memory / conservative default)"
if [ "$(uname -s)" = "Linux" ]; then
    VRAM_MIB="$(nvidia_vram_mib || true)"
    [ -n "${VRAM_MIB:-}" ] && GPU_DESC="$(nvidia_name) — ${VRAM_MIB} MiB VRAM"
fi

# ── Pick a hardware profile for Mistral AI / Qwen models ────────────────────
# Codestral-22B is opt-in only for high-VRAM cards (11+ GB).
# Bonsai-27B (3.6-3.9 GB ternary quant) is recommended on NVIDIA GPU hosts
# (CUDA backend has correct dequant kernels) but NOT on CPU-only hosts
# (measured ~2.4 tok/s with 5+ min prompt-processing stalls on Serenity).
# Qwen3-8B-Aqua is the default for CPU-only or <4 GB VRAM hosts.
#
# NOTE: VRAM thresholds are intentionally duplicated in the mu repo's
# scripts/setup-host.sh, which picks mu's model the same way, so mu and pi
# resolve to the same local model without either repo depending on the other.
#
# On 6 GB VRAM the 4.4 GB Q4_K_M Mistral-7B runs FULLY on-GPU — shrink the KV
# cache (q8_0 KV + flash attention) at ctx 8192 and it fits with ~1 GB free.
#
# Bonsai-27B (ternary quant) on NVIDIA GPU: its CUDA kernels are correct,
# and its 3.6-3.9 GB footprint fits comfortably with full GPU offload even
# on a 6 GB card, undercutting Mistral-7B Q4_K_M's 4.4 GB footprint while
# offering more parameters, so it replaces the Mistral-7B tiers below for
# any detected NVIDIA GPU.
CURRENT_HOSTNAME="$(hostname 2>/dev/null || true)"
if [[ "$CURRENT_HOSTNAME" == "Serenity" ]]; then
    echo "  ⚠ Bonsai-27B is not recommended on Serenity (CPU-only, no dGPU):"
    echo "    measured ~2.4 tok/s and 5+ min prompt-processing stalls on"
    echo "    pi's tool-heavy system prompt. Falling through to a smaller,"
    echo "    CPU-appropriate model instead."
fi
if [ -n "${VRAM_MIB:-}" ] && [ "$VRAM_MIB" -ge 16000 ] 2>/dev/null; then
    # Only use Codestral on very capable GPUs (16+ GB)
    PROFILE="codestral-q4"
    QUANT="Q4_K_M"
    PI_DEFAULT_MODEL="codestral-22b-v0.1"
    LMSTUDIO_LOAD_ARGS=""
    LMSTUDIO_LOAD_THREADS=""
elif [ -n "${VRAM_MIB:-}" ] && [ "$VRAM_MIB" -ge 11000 ] 2>/dev/null; then
    # Codestral with Q3_K_L for 11-16 GB
    PROFILE="codestral-q3"
    QUANT="Q3_K_L"
    PI_DEFAULT_MODEL="codestral-22b-v0.1"
    LMSTUDIO_LOAD_ARGS=""
    LMSTUDIO_LOAD_THREADS=""
elif [ -n "${VRAM_MIB:-}" ] && [ "$VRAM_MIB" -ge 4000 ] 2>/dev/null; then
    # NVIDIA GPU, 4-11 GB (includes the 6 GB card): Bonsai-27B via CUDA full
    # offload — its CUDA kernels are correct (unlike Vulkan), and its 3.6-3.9
    # GB footprint fits with room to spare.
    PROFILE="bonsai-27b-cuda"
    QUANT="PRELOADED"
    PI_DEFAULT_MODEL="prism-ml/Bonsai-27B-gguf/bonsai-27b.gguf"
    LMSTUDIO_LOAD_ARGS="--gpu max -c 32768"
    LMSTUDIO_LOAD_THREADS=""
else
    # No NVIDIA GPU detected (or <4 GB VRAM): qwen3-8b-aqua is the default
    # here — still GPU-offloaded where a usable GPU exists. Unlike Bonsai's
    # ternary quant, qwen3-8b-aqua's standard quant has correct Vulkan dequant
    # kernels, so on Linux hosts with an iGPU (e.g. Serenity's Intel Arc),
    # this loads fully offloaded to Vulkan instead of falling back to CPU.
    PROFILE="qwen-7b"
    QUANT="Q4_K_M"
    PI_DEFAULT_MODEL="qwen3-8b-aqua"
    LMSTUDIO_LOAD_ARGS="--gpu max -c 8192"
    LMSTUDIO_LOAD_THREADS=""
fi

echo "Host hardware profile"
echo "  Hostname:   $CURRENT_HOSTNAME"
echo "  GPU:        $GPU_DESC"
echo "  Profile:    $PROFILE"
echo "  LM Studio:  $PI_DEFAULT_MODEL ${QUANT:-}"
echo "  pi model:   $PI_DEFAULT_MODEL"
if [ -n "${LMSTUDIO_LOAD_THREADS:-}" ]; then
    echo "  CPU threads: $LMSTUDIO_LOAD_THREADS (set in LM Studio UI: Advanced → CPU Threads)"
fi
if [ -n "${LMSTUDIO_LOAD_ARGS:-}" ]; then
    echo "  Load args:  lms load $LMSTUDIO_LOAD_ARGS $PI_DEFAULT_MODEL"
fi
echo ""

# --- Run helper: execute command or show dry-run message ---------------------
run_cmd() {
    if $DRY_RUN; then
        echo "  [DRY-RUN] $*"
    else
        eval "$@"
    fi
}

# =============================================================================
# LM Studio setup (formerly setup-lmstudio.sh) — inlined below
# =============================================================================

# --- Validate dependencies for LM Studio setup -------------------------------
validate_lmstudio_dependencies() {
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

# Map model IDs to their HuggingFace repos and default quants
get_model_info() {
    local model_id="$1"
    case "$model_id" in
        codestral-22b-v0.1|codestral-latest)
            echo "mistralai/Codestral-22B-v0.1-GGUF Q4_K_M"
            ;;
        mistral-7b-instruct-v0.3|mistralai/mistral-7b-instruct-v0.3)
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
        qwen3-8b-aqua)
            echo "lmstudio-community/Qwen3-8B-Aqua-GGUF Q4_K_M"
            ;;
        bonsai-27b|bonsai|prism-ml/bonsai-27b)
            echo "prism-ml/Bonsai-27B-gguf/bonsai-27b.gguf PRELOADED"
            ;;
        *)
            echo "$model_id Q4_K_M"
            ;;
    esac
}

# Use the model and quant selected by the hardware profile above
MODEL_ID="$PI_DEFAULT_MODEL"
PROVIDER="lmstudio"

MODEL_INFO=$(get_model_info "$MODEL_ID")
MODEL_REPO=$(echo "$MODEL_INFO" | awk '{print $1}')
DEFAULT_QUANT=$(echo "$MODEL_INFO" | awk '{print $2}')

# Use QUANT from hardware profile if set, otherwise use default
if [ -n "${QUANT:-}" ]; then
    ACTUAL_QUANT="$QUANT"
else
    ACTUAL_QUANT="$DEFAULT_QUANT"
fi

# Validate quant value (skip for pre-downloaded models)
if [[ "$ACTUAL_QUANT" != "PRELOADED" ]]; then
    case "$ACTUAL_QUANT" in
        Q2_K|Q3_K_L|Q4_K_M|Q5_K_M|Q6_K|Q8_0)
            ;;
        *)
            echo "  ✗ Invalid quant: $ACTUAL_QUANT" >&2
            exit 1
            ;;
    esac
fi

# Cleanup partial downloads on failure
PARTIAL_FILE=""
cleanup_lmstudio() {
    if [ -n "${PARTIAL_FILE:-}" ] && [ -f "$PARTIAL_FILE" ]; then
        echo "  ⚠ Cleaning up partial download: $PARTIAL_FILE" >&2
        rm -f "$PARTIAL_FILE"
    fi
}

trap cleanup_lmstudio ERR EXIT

# Determine model directory and file based on model repo
MODEL_BASENAME=$(basename "$MODEL_REPO")
MODEL_BASENAME="${MODEL_BASENAME%-GGUF}"
MODEL_DIR="$HOME/.lmstudio/models/$MODEL_REPO"
MODEL_FILENAME="${MODEL_BASENAME}-${ACTUAL_QUANT}.gguf"
MODEL_FILE="$MODEL_DIR/$MODEL_FILENAME"
HF_URL="https://huggingface.co/$MODEL_REPO/resolve/main/$MODEL_FILENAME"

echo "LM Studio model configuration:"
echo "  Model: $MODEL_ID"
echo "  Repo: $MODEL_REPO"
echo "  Quant: $ACTUAL_QUANT"
echo "  Directory: $MODEL_DIR"
echo "  File: $MODEL_FILE"
echo ""

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

# Validate dependencies for LM Studio operations
validate_lmstudio_dependencies

# ── 1. Quit LM Studio if running ──────────────────────────────────────────────
echo "── LM Studio ─────────────────────────────────────────────────"
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

# ── 2. Tune LM Studio settings (guardrails off, no bundled auto-load) ────────
if [ -f "$LMSTUDIO_SETTINGS" ]; then
    echo "Tuning LM Studio settings..."
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

s.setdefault('modelLoadingGuardrails', {})['mode'] = 'off'
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

# GNU (Linux) and BSD (macOS) stat take different flags; try both.
file_size() { stat -c %s "$1" 2>/dev/null || stat -f %z "$1" 2>/dev/null || echo 0; }

# ── 3. Download model ─────────────────────────────────────────────────────────
# For pre-downloaded models (e.g. Bonsai-27B), skip download entirely.
if [[ "$ACTUAL_QUANT" == "PRELOADED" ]]; then
    BONSAI_FILE="$HOME/.lmstudio/models/$MODEL_REPO"
    if [ -f "$BONSAI_FILE" ]; then
        echo "  ✓ Model already on disk: $BONSAI_FILE"
    else
        echo "  ✗ Expected model file not found: $BONSAI_FILE" >&2
        echo "    Ensure the symlink exists: ~/.lmstudio/models/prism-ml/Bonsai-27B-gguf/bonsai-27b.gguf" >&2
        exit 1
    fi

    # Bonsai-27B: ternary quant → CUDA for NVIDIA, CPU for non-NVIDIA
    if [[ "$(uname -s)" == "Linux" ]] && command -v lms >/dev/null 2>&1; then
        BONSAI_VRAM_MIB="$(nvidia_vram_mib || true)"
        if [ -n "${BONSAI_VRAM_MIB:-}" ]; then
            BONSAI_ENGINE="llama.cpp-linux-x86_64-nvidia-cuda-avx2"
            BONSAI_ENGINE_DESC="CUDA (GPU offload, ${BONSAI_VRAM_MIB} MiB VRAM detected)"
        else
            BONSAI_ENGINE="llama.cpp-linux-x86_64-avx2"
            BONSAI_ENGINE_DESC="CPU avx2 (no NVIDIA GPU detected; Vulkan iGPU corrupts Bonsai's ternary quant)"
        fi
        if $DRY_RUN; then
            echo "  [DRY-RUN] Would run: lms runtime select $BONSAI_ENGINE --latest"
        else
            echo "Selecting $BONSAI_ENGINE_DESC llama.cpp engine for Bonsai-27B..."
            if lms runtime select "$BONSAI_ENGINE" --latest; then
                echo "  ✓ $BONSAI_ENGINE_DESC engine selected for GGUF"
            else
                echo "  ✗ Failed to select $BONSAI_ENGINE engine" >&2
                echo "    Run manually: lms runtime ls   # then: lms runtime select <alias>" >&2
                exit 1
            fi
        fi
    fi
else
    # Resumable, size-verified direct download as fallback
    curl_download_model() {
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
            echo "Downloading $MODEL_ID $ACTUAL_QUANT from $HF_URL..."
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
    }

    if $DRY_RUN; then
        echo "  [DRY-RUN] Would download: $MODEL_ID ($ACTUAL_QUANT) via direct HF download"
    else
        # Always do direct HF download, skip LM Studio hub
        curl_download_model
    fi
fi

# ── 4. Select a GPU-capable engine ────────────────────────────────────────────
# Bonsai-27B's engine is already pinned above. Every other model uses standard
# GGUF quant with correct Vulkan dequant kernels, so select Vulkan for iGPU
# offload on Linux hosts without NVIDIA.
if [[ "$ACTUAL_QUANT" != "PRELOADED" ]] && [[ "$(uname -s)" == "Linux" ]] && command -v lms >/dev/null 2>&1; then
    GPU_VRAM_MIB="$(nvidia_vram_mib || true)"
    if [ -n "${GPU_VRAM_MIB:-}" ]; then
        GPU_ENGINE="llama.cpp-linux-x86_64-nvidia-cuda-avx2"
        GPU_ENGINE_DESC="CUDA (GPU offload, ${GPU_VRAM_MIB} MiB VRAM detected)"
    else
        GPU_ENGINE="llama.cpp-linux-x86_64-vulkan-avx2"
        GPU_ENGINE_DESC="Vulkan (iGPU offload; no NVIDIA GPU detected)"
    fi
    if $DRY_RUN; then
        echo "  [DRY-RUN] Would run: lms runtime select $GPU_ENGINE --latest"
    else
        echo "Selecting $GPU_ENGINE_DESC llama.cpp engine for $MODEL_ID..."
        if lms runtime select "$GPU_ENGINE" --latest; then
            echo "  ✓ $GPU_ENGINE_DESC engine selected for GGUF"
        else
            echo "  ✗ Failed to select $GPU_ENGINE engine" >&2
            echo "    Run manually: lms runtime ls   # then: lms runtime select <alias>" >&2
            exit 1
        fi
    fi
fi

# ── 5. Remove other quants of this model ──────────────────────────────────────
# pi addresses the model by its bare id. LM Studio resolves that to a single
# GGUF only when one quant of the model sits in the folder; with two present,
# the bare id becomes ambiguous and pi's load fails. Drop every sibling quant
# except the one we just verified — and its .bak left by the template patcher.
if [[ "$ACTUAL_QUANT" != "PRELOADED" ]] && ! $DRY_RUN && [ -d "$MODEL_DIR" ]; then
    MODEL_BASE=$(basename "$MODEL_FILENAME" | sed "s|-$ACTUAL_QUANT.gguf$||")
    for stale in "$MODEL_DIR"/${MODEL_BASE}-*.gguf; do
        [ -e "$stale" ] || continue
        [ "$stale" = "$MODEL_FILE" ] && continue
        echo "  ✓ Removing other quant: $(basename "$stale")"
        rm -f "$stale" "$stale.bak"
    done
elif $DRY_RUN; then
    echo "  [DRY-RUN] Would remove other quant files from: $MODEL_DIR"
fi

# ── 6. Patch GGUF chat template ───────────────────────────────────────────────
# Mistral's v0.3 GGUF template rejects the system role. Patch is idempotent and
# MUST re-run after any re-download. `lms get` may store under a different path,
# so resolve by glob.
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
        echo "  ⚠ Model GGUF not found, skipping template patch"
    else
        for g in "${GGUFS[@]}"; do
            python3 "$SCRIPT_DIR/patch-gguf-template.py" "$g" || \
                { echo "  ✗ Failed to patch GGUF template: $g" >&2; exit 1; }
        done
    fi
fi

echo ""

# =============================================================================
# pi agent configuration (original setup-host.sh logic) — resuming below
# =============================================================================

# ── 2. pi: set the default model in the agent settings ────────────────────────
# pi reads ~/.pi/agent/settings.json (a symlink into this repo). Patch only the
# hardware-derived field, defaultModel, leaving the rest untouched. Because the
# file is shared across machines, this field is host-managed: each host's
# 'make setup-host' sets its own value, so don't commit a host-specific default.
#
# The profile picker above already accounts for Bonsai-27B (recommended only
# on NVIDIA GPU hosts, via CUDA) vs. Mistral/Codestral/Qwen, so this always
# overwrites defaultModel to match — including correcting away from a
# leftover Bonsai-27B default on a CPU-only host, or the reverse.
echo "── pi agent (~/.pi/agent/settings.json) ────────────────────"
PI_SETTINGS="$HOME/.pi/agent/settings.json"

if [ ! -f "$PI_SETTINGS" ]; then
    echo "  ⚠ $PI_SETTINGS not found — run 'make install-pi' first, then re-run."
    if $DRY_RUN; then
        echo "  [DRY-RUN] Would check if file exists"
    fi
    echo ""
    if ! $DRY_RUN; then
        exit 1
    fi
    exit 0
fi

CURRENT_MODEL_ID=""
if command -v python3 >/dev/null 2>&1; then
    CURRENT_MODEL_ID=$(python3 -c "import json; print(json.load(open('$PI_SETTINGS')).get('defaultModel', ''))") 2>/dev/null || echo ""
fi

if [[ -z "${VRAM_MIB:-}" ]] && { [[ "$CURRENT_MODEL_ID" == *Bonsai* ]] || [[ "$CURRENT_MODEL_ID" == *bonsai* ]]; }; then
    echo "  ⚠ defaultModel is '$CURRENT_MODEL_ID' but no NVIDIA GPU was detected —"
    echo "    Bonsai-27B is CPU-only here and measured ~2.4 tok/s with 5+ min"
    echo "    prompt-processing stalls (see README.md § pi agent § CPU-only"
    echo "    performance). Correcting defaultModel to '$PI_DEFAULT_MODEL'."
fi

if $DRY_RUN; then
    if command -v python3 >/dev/null 2>&1; then
        CURRENT_MODEL=$(python3 -c "import json; print(json.load(open('$PI_SETTINGS')).get('defaultModel', '<unset>'))" 2>/dev/null || echo "<error>")
        echo "  [DRY-RUN] Current defaultModel: $CURRENT_MODEL"
        echo "  [DRY-RUN] Would set defaultModel to: $PI_DEFAULT_MODEL"
    else
        echo "  [DRY-RUN] Would update defaultModel (python3 required to check current value)"
    fi
else
    python3 - "$PI_SETTINGS" "$PI_DEFAULT_MODEL" <<'PYEOF'
import json, sys
path, model = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        s = json.load(f)
except json.JSONDecodeError as e:
    print(f"  ✗ Failed to parse {path}: {e}", file=sys.stderr)
    sys.exit(1)
except FileNotFoundError:
    print(f"  ✗ File not found: {path}", file=sys.stderr)
    sys.exit(1)

if s.get("defaultModel") == model:
    print(f"  ✓ defaultModel already '{model}'")
else:
    old = s.get("defaultModel", "<unset>")
    s["defaultModel"] = model
    try:
        with open(path, "w") as f:
            json.dump(s, f, indent=2)
            f.write("\n")
        print(f"  ✓ defaultModel: {old} → {model}")
    except IOError as e:
        print(f"  ✗ Failed to write {path}: {e}", file=sys.stderr)
        sys.exit(1)
PYEOF
fi

# ── 3. pi: make sure the model is actually registered ─────────────────────────
# settings.json's defaultModel is only ever *used* if pi's model catalog
# (~/.pi/agent/models.json, also a symlink into this repo) knows about that
# model id for the "lmstudio" provider — pi does NOT query LM Studio's live
# /v1/models list, it only looks up ids configured here. If defaultModel points
# at an id missing from models.json, pi silently falls back to the first
# configured lmstudio model instead (which was Bonsai-27B here — exactly the
# CPU-only model this script exists to move hosts away from), with no error.
# So: register PI_DEFAULT_MODEL in models.json if it isn't there yet.
echo "── pi agent (~/.pi/agent/models.json) ───────────────────────"
PI_MODELS="$HOME/.pi/agent/models.json"

case "$PROFILE" in
    codestral-q4|codestral-q3) MODEL_NAME="Codestral 22B v0.1 ($ACTUAL_QUANT, via LM Studio)" ;;
    bonsai-27b-cuda)           MODEL_NAME="Bonsai 27B (ternary, Qwen3.6-27B 1-bit quant, CUDA GPU offload, via LM Studio)" ;;
    qwen-7b)                   MODEL_NAME="Qwen2.5-Coder 7B Instruct ($ACTUAL_QUANT, GPU/iGPU offload, via LM Studio)" ;;
    *)                         MODEL_NAME="$PI_DEFAULT_MODEL (via LM Studio)" ;;
esac

if [ ! -f "$PI_MODELS" ]; then
    echo "  ⚠ $PI_MODELS not found — run 'make install-pi' first, then re-run."
elif $DRY_RUN; then
    echo "  [DRY-RUN] Would ensure models.json has an lmstudio entry for '$PI_DEFAULT_MODEL'"
else
    python3 - "$PI_MODELS" "$PI_DEFAULT_MODEL" "$MODEL_NAME" <<'PYEOF'
import json, sys
path, model, name = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path) as f:
        cfg = json.load(f)
except (json.JSONDecodeError, FileNotFoundError) as e:
    print(f"  ✗ Failed to read {path}: {e}", file=sys.stderr)
    sys.exit(1)

lmstudio = cfg.setdefault("providers", {}).setdefault("lmstudio", {})
models = lmstudio.setdefault("models", [])

existing = next((m for m in models if m.get("id") == model), None)
if existing is not None:
    print(f"  ✓ models.json already registers '{model}'")
else:
    for m in models:
        m.pop("_launch", None)
    models.append({"_launch": True, "id": model, "input": ["text"], "name": name})
    try:
        with open(path, "w") as f:
            json.dump(cfg, f, indent=2)
            f.write("\n")
        print(f"  ✓ models.json: registered '{model}' ({name})")
    except IOError as e:
        print(f"  ✗ Failed to write {path}: {e}", file=sys.stderr)
        sys.exit(1)
PYEOF
fi
echo ""

if ! $DRY_RUN; then
    echo ""
    echo "Host setup complete."
else
    echo ""
    echo "[DRY-RUN] Host setup would be complete. No changes were made."
fi
