#!/usr/bin/env bash
# setup-host.sh — Tune the local LLM stack (LM Studio + pi) to this machine's
# hardware. One GPU-detection pass picks a profile, then it:
#   • LM Studio — downloads/keeps the right Qwen2.5-Coder-7B quant for the VRAM.
#   • pi        — sets defaultModel in ~/.pi/agent/settings.json (the 7B on a
#                 capable card, the snappier 3B otherwise).
#
# (mu, the other consumer of this LM Studio server, tunes itself — see
# `make setup-host` in the mu repo, which writes ~/.zshrc.mu independently.)
#
# ~/.pi/agent/* are symlinks into this repo, shared by every host (an 8 GB M2, a
# 6 GB GTX, and a 32 GB Intel Meteor Lake iGPU today). The committed configs stay
# host-agnostic: pi's defaultModel is host-managed — each machine's run sets its
# own, so that one field shouldn't be committed with a host's value.
#
# Idempotent: re-run after a GPU change and it rewrites the profile.
set -euo pipefail

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

# ── Pick a hardware profile ───────────────────────────────────────────────────
# A discrete NVIDIA card with ≥6 GB has room for the larger Q4_K_M weights. Everything
# else — the Mac, Intel iGPU machines, smaller/older cards — stays on the Q3_K_L
# default that the committed configs already encode.
#
# NOTE: the ≥6000 MiB → 7B threshold is intentionally duplicated in the mu repo's
# scripts/setup-host.sh, which picks mu's model the same way, so mu and pi resolve
# to the same local model without either repo depending on the other. Keep in sync.
if [ -n "${VRAM_MIB:-}" ] && [ "$VRAM_MIB" -ge 6000 ] 2>/dev/null; then
    PROFILE="roomy"
    QUANT="Q4_K_M"
    PI_DEFAULT_MODEL="qwen2.5-coder-7b-instruct"   # capable card → pi defaults to the 7B
else
    PROFILE="default"
    QUANT="Q3_K_L"
    PI_DEFAULT_MODEL="qwen2.5-coder-3b-instruct"   # conservative → snappier 3B default
fi

echo "Host hardware profile"
echo "  GPU:        $GPU_DESC"
echo "  Profile:    $PROFILE"
echo "  LM Studio:  Qwen2.5-Coder-7B $QUANT"
echo "  pi model:   $PI_DEFAULT_MODEL"
echo ""

# ── 1. LM Studio: download/keep the right quant ───────────────────────────────
# Hand the chosen quant down so setup-lmstudio.sh skips its own GPU probe.
echo "── LM Studio ───────────────────────────────────────────────"
QUANT="$QUANT" bash "$SCRIPT_DIR/setup-lmstudio.sh"
echo ""

# ── 2. pi: set the default model in the agent settings ────────────────────────
# pi reads ~/.pi/agent/settings.json (a symlink into this repo). Patch only the
# hardware-derived field, defaultModel, leaving the rest untouched. Because the
# file is shared across machines, this field is host-managed: each host's
# 'make setup-host' sets its own value, so don't commit a host-specific default.
echo "── pi agent (~/.pi/agent/settings.json) ────────────────────"
PI_SETTINGS="$HOME/.pi/agent/settings.json"
if [ -f "$PI_SETTINGS" ]; then
    python3 - "$PI_SETTINGS" "$PI_DEFAULT_MODEL" <<'PYEOF'
import json, sys
path, model = sys.argv[1], sys.argv[2]
with open(path) as f:
    s = json.load(f)
if s.get("defaultModel") == model:
    print(f"  ✓ defaultModel already '{model}'")
else:
    old = s.get("defaultModel", "<unset>")
    s["defaultModel"] = model
    with open(path, "w") as f:
        json.dump(s, f, indent=2)
        f.write("\n")
    print(f"  ✓ defaultModel: {old} → {model}")
PYEOF
else
    echo "  ⚠ $PI_SETTINGS not found — run 'make install-pi' first, then re-run."
fi
echo ""

echo "Host setup complete."
