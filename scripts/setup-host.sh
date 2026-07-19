#!/usr/bin/env bash
# setup-host.sh — Tune the local LLM stack (LM Studio + pi) to this machine's
# hardware for Mistral AI models. One GPU-detection pass picks a profile, then it:
#   • LM Studio — downloads/keeps the right Mistral AI model (Codestral-22B,
#                 Mistral-7B, Mixtral-8x7B) with appropriate quant for the VRAM.
#   • pi        — sets defaultModel in ~/.pi/agent/settings.json to Codestral
#                 on capable hardware, or a lighter Mistral variant otherwise.
#                 EXCEPTION: skips this entirely if defaultModel is already a
#                 Bonsai-27B id — that means the host opted into the Bonsai-27B
#                 default (see README.md § pi agent; loaded through the same
#                 LM Studio server as the Mistral AI models below, just a
#                 different model id), so leave it alone rather than
#                 overwriting it with a Mistral/Codestral pick.
#
# (mu, the other consumer of this LM Studio server, tunes itself — see
# `make setup-host` in the mu repo, which writes ~/.zshrc.mu independently.)
#
# ~/.pi/agent/* are symlinks into this repo, shared by every host. The committed
# configs stay host-agnostic: pi's defaultModel is host-managed — each machine's
# run sets its own Mistral AI model, so that field shouldn't be committed.
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

# ── Pick a hardware profile for Mistral AI models ─────────────────────────
# Mistral-7B is the safe default (4.4 GB VRAM for Q4_K_M).
# Codestral-22B is opt-in only for high-VRAM cards (11+ GB).
# Adjust based on available GPU memory.
#
# NOTE: VRAM thresholds are intentionally duplicated in the mu repo's
# scripts/setup-host.sh, which picks mu's model the same way, so mu and pi resolve
# to the same local Mistral AI model without either repo depending on the other.
#
# On 6 GB VRAM the 4.4 GB Q4_K_M Mistral-7B runs FULLY on-GPU — shrink the KV
# cache (q8_0 KV + flash attention) at ctx 8192 and it fits with ~1 GB free.
# (The old "--gpu 0.5 / full offload fails" advice was a workaround for a 12288
# fp16 KV cache spilling the card; it's 5-10x slower and no longer used. See the
# mu repo's docs/MODELS.md for the measured VRAM table.)

# ── GPU-less / CPU-only hosts (e.g. Serenity: Intel Core Ultra 5 135U, no
# dGPU) — detect by hostname since nvidia-smi returns nothing here.
#
# Bonsai-27B (3.6 GB, ternary quant) is NOT recommended on CPU-only hosts
# despite fitting in system RAM. Measured on Serenity (2026-07-19, avx2 CPU
# engine, 12 threads, ctx 32768): ~2.4 tok/s generation and ~2.8 tok/s prompt
# eval, and ingesting pi's ~1900-token tool-call system prompt routinely took
# 5+ minutes of wall-clock time with the LM Studio server showing "Prompt
# processing progress: 0.0%" the whole time. That alone was long enough to
# trip pi's default 5-minute HTTP idle timeout ("terminated" errors, silently
# retried), and even with that timeout disabled, a single trivial prompt
# round-trip still took ~3.5 minutes warm / ~13 minutes cold (retries). A 27B
# model simply has no viable CPU-only path — prefer Qwen2.5-Coder-7B-Instruct
# instead, which offloads cleanly to Vulkan iGPUs (falls through to the
# qwen-7b profile below, since VRAM_MIB is unset on these hosts).
#
# On NVIDIA GPU hosts, Bonsai-27B IS recommended instead: its ternary quant
# has correct dequantization kernels in llama.cpp's CUDA backend (unlike
# Vulkan, used for Intel/AMD iGPUs, which silently corrupts its output — see
# README.md § pi agent § GPU offload: CUDA works, Vulkan doesn't). At only
# 3.6-3.9 GB it fits comfortably with full GPU offload even on a 6 GB card,
# undercutting Mistral-7B Q4_K_M's 4.4 GB footprint while offering more
# parameters, so it now replaces the Mistral-7B tiers below for any detected
# NVIDIA GPU.
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
    PI_DEFAULT_MODEL="codestral-22b-v0.1"   # high-end → Codestral with Q4_K_M
    LMSTUDIO_LOAD_ARGS=""
    LMSTUDIO_LOAD_THREADS=""
elif [ -n "${VRAM_MIB:-}" ] && [ "$VRAM_MIB" -ge 11000 ] 2>/dev/null; then
    # Codestral with Q3_K_L for 11-16 GB
    PROFILE="codestral-q3"
    QUANT="Q3_K_L"
    PI_DEFAULT_MODEL="codestral-22b-v0.1"   # mid-high → Codestral with Q3_K_L
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
    # No NVIDIA GPU detected (or <4 GB VRAM): Qwen2.5-Coder-7B-Instruct is the
    # default here too — still GPU-offloaded where a usable GPU exists. Unlike
    # Bonsai's ternary quant, Qwen2.5-Coder's standard GGUF quant has correct
    # Vulkan dequant kernels, so on Linux hosts with an iGPU (e.g. Serenity's
    # Intel Arc), setup-lmstudio.sh selects the Vulkan engine and this loads
    # fully offloaded to it instead of falling back to CPU. Measured on
    # Serenity (2026-07-19): qwen2.5-coder-7b-instruct on Vulkan iGPU loaded
    # in ~5s and answered a trivial prompt in ~3s total, vs. Bonsai-27B's
    # CPU-only ~2.4 tok/s / 5+ min prompt-processing stalls — so the 7B, not
    # the smaller 3B, is the right fallback here.
    PROFILE="qwen-7b"
    QUANT="Q4_K_M"
    PI_DEFAULT_MODEL="qwen2.5-coder-7b-instruct"
    LMSTUDIO_LOAD_ARGS="--gpu max -c 8192"
    LMSTUDIO_LOAD_THREADS=""
fi

echo "Host hardware profile (Mistral AI optimized)"
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

# ── 1. LM Studio: download/keep the right quant ───────────────────────────────
# Hand the chosen quant down so setup-lmstudio.sh skips its own GPU probe.
echo "── LM Studio ───────────────────────────────────────────────"
if $DRY_RUN; then
    echo "  [DRY-RUN] Would run: QUANT=$QUANT bash $SCRIPT_DIR/setup-lmstudio.sh --model $PI_DEFAULT_MODEL"
else
    QUANT="$QUANT" bash "$SCRIPT_DIR/setup-lmstudio.sh" --model "$PI_DEFAULT_MODEL"
fi
echo ""

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
    CURRENT_MODEL_ID=$(python3 -c "import json; print(json.load(open('$PI_SETTINGS')).get('defaultModel', ''))" 2>/dev/null || echo "")
fi

if [[ -z "${VRAM_MIB:-}" ]] && { [[ "$CURRENT_MODEL_ID" == *Bonsai* ]] || [[ "$CURRENT_MODEL_ID" == *bonsai* ]]; }; then
    echo "  ⚠ defaultModel is '$CURRENT_MODEL_ID' but no NVIDIA GPU was detected —"
    echo "    Bonsai-27B is CPU-only here and measured ~2.4 tok/s with 5+ min"
    echo "    prompt-processing stalls (see README.md § pi agent § CPU-only"
    echo "    performance). Correcting defaultModel to '$PI_DEFAULT_MODEL'."
fi

if $DRY_RUN; then
    # Check current value in dry-run mode
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
    codestral-q4|codestral-q3) MODEL_NAME="Codestral 22B v0.1 ($QUANT, via LM Studio)" ;;
    bonsai-27b-cuda)           MODEL_NAME="Bonsai 27B (ternary, Qwen3.6-27B 1-bit quant, CUDA GPU offload, via LM Studio)" ;;
    qwen-7b)                   MODEL_NAME="Qwen2.5-Coder 7B Instruct ($QUANT, GPU/iGPU offload, via LM Studio)" ;;
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
