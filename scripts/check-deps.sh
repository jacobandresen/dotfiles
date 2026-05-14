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
need "neovim"         nvim      "scripts/setup.sh"
need "git"            git       "scripts/setup.sh"
need "make"           make      "scripts/setup.sh"
need "gcc"            gcc       "scripts/setup.sh"

echo ""
echo "Language runtimes"
need "node"           node      "scripts/setup.sh"
need "npm"            npm       "setup.sh (included with node)"
need "python3"        python3   "scripts/setup.sh"

echo ""
echo "Tools"
need "fzf"            fzf       "scripts/setup.sh"
need "ripgrep (rg)"   rg        "setup.sh  [telescope live_grep]"
need "fd"             fd        "setup.sh  [telescope find_files]"
need "jq"             jq        "setup.sh  [JSON formatting]"
need "fpc"            fpc       "setup.sh  [Free Pascal]"

echo ""
echo "Static analysis"
need "java"           java          "scripts/setup.sh  [sonarqube/scanner runtime]"
need "sonar-scanner"  sonar-scanner "scripts/setup.sh"
if [ -d /opt/sonarqube ]; then
  ok "sonarqube CE  (/opt/sonarqube)"
else
  miss "sonarqube CE" "scripts/setup.sh  [local analysis server]"
fi

echo ""
echo "AI backend"
need "pi"             pi        "npm install -g @earendil-works/pi-coding-agent"
need "ollama"         ollama    "setup.sh  [local model server]"

echo ""
echo "AI models"
if command -v ollama > /dev/null 2>&1; then
  if ollama list 2>/dev/null | grep -q 'gemma4'; then
    ok "gemma4"
  else
    miss "gemma4" "ollama pull gemma4"
  fi
else
  miss "gemma4" "install ollama first"
fi

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "All $PASS dependencies present."
else
  echo "$FAIL missing, $PASS present."
  echo "Run scripts/setup.sh to install system packages."
  echo "For pi: npm install -g @earendil-works/pi-coding-agent"
fi

[ "$FAIL" -eq 0 ]
