#!/usr/bin/env bash
# install-bonsai.sh — Set up PrismML's Bonsai 27B in Ollama.
#
# Bonsai 27B (https://huggingface.co/prism-ml/Bonsai-27B-gguf) is a 1-bit
# compression of Qwen3.6-27B, Apache 2.0. The Q1_0 language model is 3.8GB,
# which is the only reason a 27B-class model is worth attempting on an 8GB
# Mac at all.
#
# Why this script exists instead of a plain `ollama pull`:
#
#   `ollama pull hf.co/prism-ml/Bonsai-27B-gguf:Q1_0` also pulls the 629MB
#   Q8_0 vision projector, and Ollama loads the projector into VRAM whether
#   or not you ever send it an image. On this 8GB M2 that pushed the model
#   past the ~5.4GB Metal budget, so only 46 of 65 layers were offloaded and
#   the rest ran on CPU. Measured: 1.0 tok/s.
#
#   Rebuilding the same weights without the projector puts all 65 layers on
#   the GPU: 7-8 tok/s, a ~7x difference. So the default `bonsai-27b` here is
#   text-only. Pass --with-vision if you actually want images and can live
#   with the CPU spill.
#
# The FROM path points at the blob Ollama already downloaded rather than a
# second copy of the file, so the text-only build costs no extra disk.
#
#   ./install-bonsai.sh                # text-only (recommended on 8GB)
#   ./install-bonsai.sh --with-vision  # keep the projector, accept the spill
#   ./install-bonsai.sh --name foo     # name it something else
set -euo pipefail

UPSTREAM="hf.co/prism-ml/Bonsai-27B-gguf:Q1_0"
MODEL_NAME="bonsai-27b"
WITH_VISION=false

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OLLAMA_HOST_URL="${OLLAMA_HOST:-http://127.0.0.1:11434}"
case "$OLLAMA_HOST_URL" in http*) ;; *) OLLAMA_HOST_URL="http://$OLLAMA_HOST_URL" ;; esac

while [ $# -gt 0 ]; do
	case "$1" in
		-h|--help)
			sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'
			exit 0
			;;
		--with-vision) WITH_VISION=true; shift ;;
		--name) MODEL_NAME="$2"; shift 2 ;;
		*) echo "Unknown option: $1" >&2; exit 1 ;;
	esac
done

echo "============================================================================="
echo "Bonsai 27B (1-bit Qwen3.6-27B) → Ollama model '$MODEL_NAME'"
echo "============================================================================="

# --- 1. Ollama must be installed and answering -------------------------------
if ! command -v ollama >/dev/null 2>&1; then
	echo "  ✗ ollama not found — run 'make deps' first" >&2
	exit 1
fi

# The Q1_0 quant type and the qwen35 architecture both need a recent Ollama;
# the community packaging notes 0.32.5 as the floor. Warn rather than block,
# since the version string format has changed before.
VERSION="$(ollama --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
if [ -n "$VERSION" ]; then
	if [ "$(printf '%s\n0.32.5\n' "$VERSION" | sort -V | head -1)" != "0.32.5" ]; then
		echo "  ⚠ Ollama $VERSION is older than 0.32.5 — Q1_0 may not load"
	else
		echo "  ✓ Ollama $VERSION"
	fi
fi

if ! curl -sf --max-time 3 "$OLLAMA_HOST_URL/api/version" >/dev/null 2>&1; then
	echo "  ⚠ Ollama not responding at $OLLAMA_HOST_URL — starting it..."
	open -a Ollama 2>/dev/null || (ollama serve >/dev/null 2>&1 &)
	for _ in 1 2 3 4 5 6 7 8 9 10; do
		curl -sf --max-time 2 "$OLLAMA_HOST_URL/api/version" >/dev/null 2>&1 && break
		sleep 1
	done
	if ! curl -sf --max-time 2 "$OLLAMA_HOST_URL/api/version" >/dev/null 2>&1; then
		echo "  ✗ could not reach Ollama at $OLLAMA_HOST_URL" >&2
		exit 1
	fi
fi
echo "  ✓ Ollama server responding at $OLLAMA_HOST_URL"

# --- 2. Pull the upstream weights --------------------------------------------
echo ""
echo "--- Upstream weights ---"
if ollama list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$UPSTREAM"; then
	echo "  ✓ $UPSTREAM already pulled"
else
	echo "  ↓ pulling $UPSTREAM (4.4GB: 3.8GB model + 0.63GB vision projector)..."
	ollama pull "$UPSTREAM"
fi

if $WITH_VISION; then
	echo ""
	echo "  → --with-vision: using $UPSTREAM as-is (projector included)."
	echo "    Expect partial GPU offload and single-digit-fraction tok/s on 8GB."
	MODELFILE_FROM="FROM $UPSTREAM"
else
	# --- 3. Locate the language-model blob -----------------------------------
	# The manifest lists two layers; we want the one whose mediaType ends in
	# '.model' and deliberately not the '.projector' one.
	MODELS_DIR="${OLLAMA_MODELS:-$HOME/.ollama/models}"
	MANIFEST="$MODELS_DIR/manifests/hf.co/prism-ml/Bonsai-27B-gguf/Q1_0"
	if [ ! -f "$MANIFEST" ]; then
		echo "  ✗ manifest not found at $MANIFEST" >&2
		echo "    Set OLLAMA_MODELS if your model store lives elsewhere." >&2
		exit 1
	fi
	DIGEST="$(python3 -c "
import json, sys
m = json.load(open('$MANIFEST'))
for l in m['layers']:
    if l['mediaType'].endswith('.model'):
        print(l['digest'].replace(':', '-'))
        break
else:
    sys.exit(1)
")" || { echo "  ✗ no model layer in manifest" >&2; exit 1; }

	BLOB="$MODELS_DIR/blobs/$DIGEST"
	[ -f "$BLOB" ] || { echo "  ✗ blob missing: $BLOB" >&2; exit 1; }
	echo "  ✓ language-model blob: $BLOB"
	MODELFILE_FROM="FROM $BLOB"
fi

# --- 4. Size the context window ----------------------------------------------
# Bonsai's hybrid attention makes the KV cache unusually cheap — only 16 of
# its 64 layers are attention, so 4096 tokens cost ~136MiB at q8_0. The
# ceiling is the weights, not the cache. Measured on this 8GB M2:
#   8192  -> 65/65 layers on GPU, ~7 tok/s
#   16384 -> 64/65 layers on GPU, ~8 tok/s
#   32768 -> 55/65 layers on GPU, ~0.8 tok/s   <- cliff
# so 8gb stays at 8192 with headroom for an editor. The larger tiers are
# extrapolated from the weight footprint, not measured.
PROFILE="$("$SCRIPT_DIR/detect-ram-profile.sh")"
case "$PROFILE" in
	32gb) NUM_CTX=65536 ;;
	16gb) NUM_CTX=32768 ;;
	*)    NUM_CTX=8192 ;;
esac
echo "  → RAM profile $PROFILE → num_ctx $NUM_CTX (model's own ceiling is 262144)"

# --- 5. Build the model ------------------------------------------------------
# Sampler values are the ones on PrismML's model card.
echo ""
echo "--- Building '$MODEL_NAME' ---"
TMP_MODELFILE="$(mktemp)"
trap 'rm -f "$TMP_MODELFILE"' EXIT
cat > "$TMP_MODELFILE" <<EOF
$MODELFILE_FROM

PARAMETER num_ctx $NUM_CTX
PARAMETER temperature 0.7
PARAMETER top_k 20
PARAMETER top_p 0.95
PARAMETER min_p 0.0
PARAMETER repeat_penalty 1.0
EOF

ollama create "$MODEL_NAME" -f "$TMP_MODELFILE"
echo "  ✓ created '$MODEL_NAME'"

echo ""
echo "============================================================================="
echo "Done. Try it:"
echo "    ollama run $MODEL_NAME"
echo "    DOTFILES_CODING_MODEL=$MODEL_NAME make setup-host   # point pi at it"
echo "============================================================================="
