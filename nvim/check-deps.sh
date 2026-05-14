#!/bin/sh
# check-deps.sh — verify every dependency required by this Neovim config.
# Exit 0 if all found, 1 if anything is missing.

PASS=0
FAIL=0

ok()   { printf "  [OK]  %s\n"           "$1"; PASS=$((PASS + 1)); }
miss() { printf "  [!!]  %-24s %s\n"     "$1" "$2"; FAIL=$((FAIL + 1)); }

need() {
  _label="$1"; _cmd="$2"; _hint="$3"
  if command -v "$_cmd" > /dev/null 2>&1; then
    ok "$_label"
  else
    miss "$_label" "$_hint"
  fi
}

echo "Core"
need "neovim"         nvim      "setup.sh"
need "git"            git       "setup.sh"
need "make"           make      "setup.sh"
need "gcc"            gcc       "setup.sh"

echo ""
echo "Language runtimes"
need "node"           node      "setup.sh"
need "npm"            npm       "setup.sh (included with node)"
need "python3"        python3   "setup.sh"

echo ""
echo "Tools"
need "fzf"            fzf       "setup.sh"
need "ripgrep (rg)"   rg        "setup.sh  [telescope live_grep]"
need "fd"             fd        "setup.sh  [telescope find_files]"
need "jq"             jq        "setup.sh  [JSON formatting]"
need "fpc"            fpc       "setup.sh  [Free Pascal]"

echo ""
echo "AI backend"
need "pi"             pi        "npm install -g @earendil-works/pi-coding-agent"

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "All $PASS dependencies present."
else
  echo "$FAIL missing, $PASS present."
  echo "Run ./setup.sh to install system packages."
  echo "For pi: npm install -g @earendil-works/pi-coding-agent"
fi

[ "$FAIL" -eq 0 ]
