#!/usr/bin/env bash
# setup-host.sh — Tune the local LLM stack (LM Studio + pi) to this machine's
# hardware for Mistral AI models. One GPU-detection pass picks a profile, then it:
#   • LM Studio — downloads/keeps the right Mistral AI model (Codestral-22B,
#                 Mistral-7B, Mixtral-8x7B) with appropriate quant for the VRAM.
#   • pi        — sets defaultModel in ~/.pi/agent/settings.json to Codestral
#                 on capable hardware, or a lighter Mistral variant otherwise.
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
# Codestral-22B needs ~14 GB VRAM for Q4_K_M, ~11 GB for Q3_K_L.
# Mistral-7B needs ~4.4 GB for Q4_K_M, ~3.8 GB for Q3_K_L.
# Adjust based on available GPU memory.
#
# NOTE: VRAM thresholds are intentionally duplicated in the mu repo's
# scripts/setup-host.sh, which picks mu's model the same way, so mu and pi resolve
# to the same local Mistral AI model without either repo depending on the other.
if [ -n "${VRAM_MIB:-}" ] && [ "$VRAM_MIB" -ge 16000 ] 2>/dev/null; then
    PROFILE="codestral-q4"
    QUANT="Q4_K_M"
    PI_DEFAULT_MODEL="codestral-22b-v0.1"   # capable card → Codestral with Q4_K_M
elif [ -n "${VRAM_MIB:-}" ] && [ "$VRAM_MIB" -ge 11000 ] 2>/dev/null; then
    PROFILE="codestral-q3"
    QUANT="Q3_K_L"
    PI_DEFAULT_MODEL="codestral-22b-v0.1"   # mid-range → Codestral with Q3_K_L
elif [ -n "${VRAM_MIB:-}" ] && [ "$VRAM_MIB" -ge 6000 ] 2>/dev/null; then
    PROFILE="mistral-7b"
    QUANT="Q4_K_M"
    PI_DEFAULT_MODEL="mistral-7b-instruct-v0.2"   # 6-11 GB → Mistral 7B
elif [ -n "${VRAM_MIB:-}" ] && [ "$VRAM_MIB" -ge 4000 ] 2>/dev/null; then
    PROFILE="mistral-7b-q3"
    QUANT="Q3_K_L"
    PI_DEFAULT_MODEL="mistral-7b-instruct-v0.2"   # 4-6 GB → Mistral 7B Q3
else
    PROFILE="qwen-3b"
    QUANT="Q3_K_L"
    PI_DEFAULT_MODEL="qwen2.5-coder-3b-instruct"   # <4 GB → lightweight fallback
fi

echo "Host hardware profile (Mistral AI optimized)"
echo "  GPU:        $GPU_DESC"
echo "  Profile:    $PROFILE"
echo "  LM Studio:  $PI_DEFAULT_MODEL $QUANT"
echo "  pi model:   $PI_DEFAULT_MODEL"
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
    echo "  [DRY-RUN] Would run: QUANT=$QUANT bash $SCRIPT_DIR/setup-lmstudio.sh"
else
    QUANT="$QUANT" bash "$SCRIPT_DIR/setup-lmstudio.sh"
fi
echo ""

# ── 2. pi: set the default model in the agent settings ────────────────────────
# pi reads ~/.pi/agent/settings.json (a symlink into this repo). Patch only the
# hardware-derived field, defaultModel, leaving the rest untouched. Because the
# file is shared across machines, this field is host-managed: each host's
# 'make setup-host' sets its own value, so don't commit a host-specific default.
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
    print(f"  ✗ Failed to parse {path}: {e}" >&2)
    sys.exit(1)
except FileNotFoundError:
    print(f"  ✗ File not found: {path}" >&2)
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
        print(f"  ✗ Failed to write {path}: {e}" >&2)
        sys.exit(1)
PYEOF
fi

if ! $DRY_RUN; then
    echo ""
    echo "Host setup complete."
else
    echo ""
    echo "[DRY-RUN] Host setup would be complete. No changes were made."
fi
