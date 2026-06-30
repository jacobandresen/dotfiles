#!/usr/bin/env bash
# setup-jupyter.sh — Provision the Python side of the Neovim Jupyter stack.
#
# Builds a dedicated venv (~/.virtualenvs/neovim) that serves two roles:
#   1. Neovim's python3 host for molten-nvim (needs pynvim + jupyter_client).
#   2. A registered "neovim" Jupyter kernel (ipykernel + the scientific stack).
# Also installs the `jupytext` CLI on PATH (for jupytext.nvim) and symlinks the
# repo's jupytext config. Standalone on purpose — not part of `make install`.
set -euo pipefail

# --- Error handling helpers --------------------------------------------------

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Provision Python venv and Jupyter kernel for Neovim.

Options:
  -h, --help     Show this help message and exit
  -n, --dry-run  Show what would be done without making changes
  -v, --verbose  Enable verbose output

Examples:
  $(basename "$0")              # Run full setup
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

# Cleanup on error
trap 'echo "\n✗ Jupyter setup failed. Check errors above." >&2' ERR

# Validate dependencies
validate_dependencies() {
    local missing=()
    
    command -v python3 >/dev/null 2>&1 || missing+=("python3")
    command -v pip >/dev/null 2>&1 || missing+=("pip")
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo "  ✗ Missing dependencies: ${missing[*]}" >&2
        echo "  Install with:" >&2
        echo "    Ubuntu/Debian: sudo apt-get install python3 python3-pip python3-venv" >&2
        echo "    Arch:          sudo pacman -S python python-pip" >&2
        echo "    macOS:        brew install python" >&2
        exit 1
    fi
}

validate_dependencies

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV="$HOME/.virtualenvs/neovim"

# ── Base interpreter ──────────────────────────────────────────────────────────
# Linux: the real system python (/usr/bin/python3) so --system-site-packages
# inherits the distro's jupyter_client/ipykernel/numpy/matplotlib instead of
# rebuilding them (and dodging wheel pain on bleeding-edge Pythons). macOS: the
# Homebrew python3 on PATH.
case "$(uname -s)" in
  Darwin) BASE_PY="$(command -v python3)";;
  Linux)  BASE_PY="/usr/bin/python3";;
  *) echo "  ✗ Unsupported OS: $(uname -s)" >&2; exit 1;;
esac
[ -x "$BASE_PY" ] || { echo "  ✗ No python3 at $BASE_PY" >&2; exit 1; }

if $DRY_RUN; then
    echo "  [DRY-RUN] Base Python: $BASE_PY"
    echo "  [DRY-RUN] Target venv: $VENV"
fi

# ── 1. Create / reuse the venv ────────────────────────────────────────────────
if [ -x "$VENV/bin/python" ]; then
    echo "  ✓ venv already present at $VENV"
else
    if $DRY_RUN; then
        echo "  [DRY-RUN] Would create venv at $VENV with --system-site-packages"
    else
        echo "Creating venv at $VENV (base: $BASE_PY)..."
        mkdir -p "$(dirname "$VENV")" || { echo "  ✗ Failed to create directory: $(dirname "$VENV")" >&2; exit 1; }
        "$BASE_PY" -m venv --system-site-packages "$VENV" || \
            { echo "  ✗ Failed to create venv" >&2; exit 1; }
        echo "  ✓ venv created"
    fi
fi
PY="$VENV/bin/python"

# ── 2. Install Python packages ────────────────────────────────────────────────
# pynvim is the only hard requirement (pure-Python, always installs). The rest
# are best-effort: most are inherited from the system via --system-site-packages,
# and a missing wheel for one shouldn't abort the whole setup.

if $DRY_RUN; then
    echo "  [DRY-RUN] Would install Python packages:"
    echo "    - pynvim (required)"
    echo "    - ipykernel, jupyter_client, nbformat, numpy, matplotlib, pandas"
    echo "    - pillow, cairosvg, pnglatex, plotly, kaleido, ipywidgets (best-effort)"
else
    echo "Installing Python packages into the venv..."
    "$PY" -m pip install --quiet --upgrade pip || \
        { echo "  ✗ Failed to upgrade pip" >&2; exit 1; }
    "$PY" -m pip install --quiet pynvim || { echo "  ✗ pynvim failed to install" >&2; exit 1; }
    echo "  ✓ pynvim"

    best_effort() {
        if "$PY" -m pip install --quiet "$1" 2>/dev/null; then
            echo "  ✓ $1"
        else
            echo "  ⚠ skipped $1 (no wheel for this Python / build failed)"
        fi
    }
    # Kernel + image-output helpers. ipykernel/jupyter_client/numpy/matplotlib are
    # usually inherited from the system; reinstalling here is a harmless no-op.
    for pkg in ipykernel jupyter_client nbformat numpy matplotlib pandas \
               pillow cairosvg pnglatex plotly kaleido ipywidgets; do
        best_effort "$pkg"
    done
fi

# ── 3. Register the "neovim" Jupyter kernel ───────────────────────────────────
if $DRY_RUN; then
    echo "  [DRY-RUN] Would register 'neovim' Jupyter kernel pointing to: $VENV"
else
    if "$PY" -c "import ipykernel" 2>/dev/null; then
        echo "Registering the 'neovim' Jupyter kernel..."
        "$PY" -m ipykernel install --user --name neovim \
            --display-name "Python 3 (neovim)" >/dev/null || \
            { echo "  ✗ Failed to register kernel" >&2; exit 1; }
        echo "  ✓ kernel 'neovim' -> $VENV"
    else
        echo "  ⚠ ipykernel unavailable; skipped kernel registration"
    fi
fi

# ── 4. jupytext CLI on PATH (used by jupytext.nvim) ───────────────────────────
# jupytext.nvim only needs plain format conversion, but inject jupyter_client +
# nbformat so kernel-aware CLI ops (`--set-kernel`, `--sync`) also work.
if $DRY_RUN; then
    echo "  [DRY-RUN] Would ensure jupytext is installed (via pipx if available)"
else
    if command -v jupytext >/dev/null 2>&1; then
        echo "  ✓ jupytext already on PATH"
    elif command -v pipx >/dev/null 2>&1; then
        echo "Installing jupytext via pipx..."
        pipx install jupytext >/dev/null || { echo "  ✗ pipx install failed" >&2; exit 1; }
        pipx inject jupytext jupyter_client nbformat >/dev/null 2>&1 || true
        echo "  ✓ jupytext (pipx)"
    else
        echo "  ⚠ pipx not found — install jupytext yourself (e.g. 'pipx install jupytext')"
    fi
fi

# ── 5. Symlink the jupytext config (backup any existing file) ─────────────────
JCONF_SRC="$REPO_DIR/jupyter/jupytext.toml"
JCONF_DST="$HOME/.jupyter/jupytext.toml"

if $DRY_RUN; then
    echo "  [DRY-RUN] Would symlink jupytext config:"
    echo "    $JCONF_DST -> $JCONF_SRC"
else
    mkdir -p "$HOME/.jupyter" || { echo "  ✗ Failed to create directory: $HOME/.jupyter" >&2; exit 1; }
    if [ -L "$JCONF_DST" ]; then
        echo "  ✓ ~/.jupyter/jupytext.toml already symlinked"
    elif [ -e "$JCONF_DST" ]; then
        mv "$JCONF_DST" "$JCONF_DST.bak" || { echo "  ✗ Failed to backup existing config" >&2; exit 1; }
        ln -s "$JCONF_SRC" "$JCONF_DST" || { echo "  ✗ Failed to create symlink" >&2; exit 1; }
        echo "  ✓ backed up old jupytext.toml -> jupytext.toml.bak, linked repo copy"
    else
        ln -s "$JCONF_SRC" "$JCONF_DST" || { echo "  ✗ Failed to create symlink" >&2; exit 1; }
        echo "  ✓ ~/.jupyter/jupytext.toml -> $JCONF_SRC"
    fi
fi

if $DRY_RUN; then
    echo ""
    echo "[DRY-RUN] Jupyter setup would be complete. No changes were made."
    echo "  To execute: run without --dry-run flag"
else
    echo ""
    echo "Jupyter setup complete."
    echo "  • Neovim python host: $VENV/bin/python3 (auto-detected by options.lua)"
    echo "  • Launch nvim once so molten's :UpdateRemotePlugins build can run."
    echo "    (If :Molten* commands error on first use, run :UpdateRemotePlugins and restart nvim.)"
    echo "  • Open an .ipynb (or a .py with '# %%' cells), then <leader>ji to start a kernel."
    echo "  • JupyterLab is unchanged: run 'jupyter lab' as usual."
fi
