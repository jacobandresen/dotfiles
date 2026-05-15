#!/usr/bin/env bash
# turbo-ralph.sh — Autonomous goal-to-code orchestrator
#
# USAGE
#   turbo-ralph.sh [OPTIONS] "project goal"
#
# OPTIONS
#   -d, --dir PATH           Create/enter PATH before running (recommended for new apps)
#   -n, --max-iterations N   Maximum code-agent iterations (default: 10)
#       --force              Skip the existing-project guard
#   -h, --help               Show this help and exit
#
# DESCRIPTION
#   Drives an autonomous coding loop from a plain-English goal:
#     1. Runs /skill:task-planner to produce a tracked PLAN.md
#     2. Repeatedly runs /skill:code-agent until all tasks are [x]
#        or the iteration limit is reached
#
#   Designed for small, self-contained apps in a standalone directory.
#   Use --dir to create/enter a dedicated directory; Ralph will refuse to
#   run in an existing project unless --force is passed or PLAN.md is present
#   (which means a prior Ralph session can safely be resumed).
#
#   Each iteration's output is logged under .ralph/ for review.
#
# EXIT CODES
#   0   Goal complete (all tasks done or PLAN.md archived by agent)
#   1   Bad arguments or planner failed to produce PLAN.md
#   2   Max iterations reached with tasks still remaining
#
# CONTACT
#   Jacob Andresen <jacob.andresen@gmail.com>

set -euo pipefail

MAX_ITER=10
GOAL=""
TARGET_DIR=""
FORCE=0

# ── Banner ────────────────────────────────────────────────────────────────────

# 4-frame dance animation (13 lines each). \033[K clears trailing chars on redraw.
_ralph_frame() {
  local H='\033[90m' F='\033[1;33m' S='\033[0;34m' R='\033[0m' K='\033[K'
  case "$1" in
    1)  # neutral
      printf "${H}       _____________${R}${K}\n"
      printf "${H}      |  _________  |${R}${K}\n"
      printf "${H}      | |${F}         ${H}| |${R}${K}\n"
      printf "${H}      | |${F}  o   o  ${H}| |${R}${K}\n"
      printf "${H}      | |${F}    ^    ${H}| |${R}${K}\n"
      printf "${H}      | |${F}  (   )  ${H}| |${R}${K}\n"
      printf "${H}      | |${F}  -----  ${H}| |${R}${K}\n"
      printf "${H}      | |_________| |${R}${K}\n"
      printf "${H}      |_____________|${R}${K}\n"
      printf "            ${F}|||${R}${K}\n"
      printf "      ${S}_____|||||_____${R}${K}\n"
      printf "      ${S}|             |${R}${K}\n"
      printf "      ${S}|_____________|${R}${K}\n"
      ;;
    2)  # arms raised \  /
      printf "${H}  \\    _____________    /${R}${K}\n"
      printf "${H}   \\  |  _________  |  /${R}${K}\n"
      printf "${H}      | |${F}         ${H}| |${R}${K}\n"
      printf "${H}      | |${F}  o   o  ${H}| |${R}${K}\n"
      printf "${H}      | |${F}    ^    ${H}| |${R}${K}\n"
      printf "${H}      | |${F}  (   )  ${H}| |${R}${K}\n"
      printf "${H}      | |${F}  -----  ${H}| |${R}${K}\n"
      printf "${H}      | |_________| |${R}${K}\n"
      printf "${H}      |_____________|${R}${K}\n"
      printf "            ${F}|||${R}${K}\n"
      printf "      ${S}_____|||||_____${R}${K}\n"
      printf "      ${S}|             |${R}${K}\n"
      printf "      ${S}|_____________|${R}${K}\n"
      ;;
    3)  # arms out to sides  / \
      printf "${H}       _____________${R}${K}\n"
      printf "${H}      |  _________  |${R}${K}\n"
      printf "${H}  /   | |${F}         ${H}| |   \\${R}${K}\n"
      printf "${H}  \\   | |${F}  o   o  ${H}| |   /${R}${K}\n"
      printf "${H}      | |${F}    ^    ${H}| |${R}${K}\n"
      printf "${H}      | |${F}  (   )  ${H}| |${R}${K}\n"
      printf "${H}      | |${F}  -----  ${H}| |${R}${K}\n"
      printf "${H}      | |_________| |${R}${K}\n"
      printf "${H}      |_____________|${R}${K}\n"
      printf "            ${F}|||${R}${K}\n"
      printf "      ${S}_____|||||_____${R}${K}\n"
      printf "      ${S}|             |${R}${K}\n"
      printf "      ${S}|_____________|${R}${K}\n"
      ;;
    4)  # feet apart, arms low
      printf "${H}       _____________${R}${K}\n"
      printf "${H}      |  _________  |${R}${K}\n"
      printf "${H}      | |${F}         ${H}| |${R}${K}\n"
      printf "${H}      | |${F}  o   o  ${H}| |${R}${K}\n"
      printf "${H}      | |${F}    ^    ${H}| |${R}${K}\n"
      printf "${H}      | |${F}  (   )  ${H}| |${R}${K}\n"
      printf "${H}      | |${F}  -----  ${H}| |${R}${K}\n"
      printf "${H}      | |_________| |${R}${K}\n"
      printf "${H}      |_____________|${R}${K}\n"
      printf "        /   ${F}|||${R}   \\${K}\n"
      printf "      ${S}_____|||||_____${R}${K}\n"
      printf "     ${S}/|             |\\${R}${K}\n"
      printf "      ${S}|_____________|${R}${K}\n"
      ;;
  esac
}

print_banner() {
  local C='\033[1;36m'   # bold cyan  — title box
  local T='\033[1;37m'   # bold white — title text
  local G='\033[0;32m'   # green      — label
  local R='\033[0m'

  printf "\n"

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local ralph_img="$script_dir/ralph.png"

  if command -v img2txt &>/dev/null && [[ -f "$ralph_img" ]]; then
    img2txt --width=36 --height=28 --format=ansi "$ralph_img"
  else
    local RALPH_LINES=13
    _ralph_frame 1
    if [[ -t 1 ]]; then
      for frame in 2 3 4 3 2 1 2 3 4 3 2 1; do
        sleep 0.13
        printf "\033[%dA" "$RALPH_LINES"
        _ralph_frame "$frame"
      done
    fi
  fi

  printf "\n"
  printf "  ${C}╔═════════════════════════╗${R}\n"
  printf "  ${C}║${T}       TURBO  RALPH       ${C}║${R}\n"
  printf "  ${C}╚═════════════════════════╝${R}\n"
  printf "\n"
  [[ -n "${1:-}" ]] && printf "  ${G}goal:${R} %s\n\n" "$1"

  print_ralph_quote
}

print_ralph_quote() {
  local Q='\033[3;33m'   # italic yellow — quote
  local E='\033[90m'     # dim grey     — episode
  local R='\033[0m'

  mapfile -t _ralph_quotes <<'RALPH_QUOTES'
"Me fail English? That's unpossible."|S6E8 · Lisa on Ice
"Hi, Super Nintendo Chalmers! I'm learneding."|S10E7 · Lisa Gets an 'A'
"Oh boy, sleep! That's where I'm a Viking!"|S7E5 · Lisa the Vegetarian
"That's where I saw the leprechaun. He told me to burn things."|S9E18 · This Little Wiggy
"My cat's breath smells like cat food."|S4E15 · I Love Lisa
"The doctor said I wouldn't have so many nosebleeds if I kept my finger outta there."|S4E15 · I Love Lisa
"I'm Idaho!"|S5E10 · $pringfield
"If Mommy's purse didn't belong in the microwave, why did it fit?"|S26E22 · Mathlete's Feat
"Dear Miss Hoover, you have Lyme disease. We miss you."|S2E19 · Lisa's Substitute
"I wet my arm pants."|S22E15 · The Scorpion's Tale
"I cheated wrong. I copied the Lisa name and used the Ralph answers."|S21E15 · Stealing First Base
"Slow down, Bart! My legs don't know how to be as long as yours."|S9E18 · This Little Wiggy
"The baby looked at me."|S8E19 · Grade School Confidential
"I'm a Star Wars."|S21E10 · Once Upon a Time in Springfield
RALPH_QUOTES

  local entry="${_ralph_quotes[RANDOM % ${#_ralph_quotes[@]}]}"
  local quote="${entry%%|*}"
  local episode="${entry##*|}"

  printf "  ${Q}%s${R}\n" "$quote"
  printf "  ${E}— %s${R}\n\n" "$episode"
}

usage() {
  print_banner
  cat <<'EOF'
USAGE
  turbo-ralph.sh [OPTIONS] "project goal"

OPTIONS
  -d, --dir PATH           Create/enter PATH before running (recommended for new apps)
  -n, --max-iterations N   Maximum code-agent iterations (default: 10)
      --force              Skip the existing-project guard
  -h, --help               Show this help and exit

DESCRIPTION
  Drives an autonomous coding loop from a plain-English goal:
    1. Runs /skill:task-planner to produce a tracked PLAN.md
    2. Repeatedly runs /skill:code-agent until all tasks are [x]
       or the iteration limit is reached

  Designed for small, self-contained apps in a standalone directory.
  Use --dir to create/enter a dedicated directory. Ralph will refuse to
  run in an existing project unless --force is passed or a PLAN.md from a
  prior session is present (resume is always allowed).

  Each iteration's output is logged under .ralph/ for review.

EXIT CODES
  0   Goal complete (all tasks done or PLAN.md archived by agent)
  1   Bad arguments or planner failed to produce PLAN.md
  2   Max iterations reached with tasks still remaining

CONTACT
  Jacob Andresen <jacob.andresen@gmail.com>
EOF
  exit "${1:-0}"
}

die() {
  echo "turbo-ralph: error: $*" >&2
  exit 1
}

# ── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dir)
      [[ -n "${2-}" ]] || die "--dir requires a path"
      TARGET_DIR="$2"
      shift 2
      ;;
    -n|--max-iterations)
      [[ "${2-}" =~ ^[0-9]+$ ]] || die "--max-iterations requires a positive integer"
      MAX_ITER="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage 0
      ;;
    --)
      shift
      GOAL="$*"
      break
      ;;
    -*)
      die "unknown option: $1 (try --help)"
      ;;
    *)
      GOAL="$1"
      shift
      ;;
  esac
done

[[ -n "$GOAL" ]] || { echo "turbo-ralph: error: project goal is required" >&2; usage 1; }

# ── Directory setup ───────────────────────────────────────────────────────────
if [[ -n "$TARGET_DIR" ]]; then
  mkdir -p "$TARGET_DIR"
  cd "$TARGET_DIR"
fi

# ── Standalone guard ──────────────────────────────────────────────────────────
_check_standalone() {
  # Always allow resuming a prior Ralph session
  [[ -f PLAN.md ]] && return 0
  # Skip guard when --force is set
  (( FORCE )) && return 0

  local file_count=0 git_commits=0
  file_count=$(find . -maxdepth 1 ! -name '.' ! -name '.*' | wc -l)
  if git rev-parse --git-dir &>/dev/null; then
    git_commits=$(git rev-list --count HEAD 2>/dev/null || echo 0)
  fi

  if (( file_count > 5 || git_commits > 0 )); then
    echo "turbo-ralph: '$(pwd)' looks like an existing project (files: $file_count, git commits: $git_commits)" >&2
    echo "  Turbo Ralph is designed for small apps in a standalone directory." >&2
    echo "  Use --dir <path> to target a fresh directory, or --force to proceed anyway." >&2
    exit 1
  fi
}
_check_standalone

print_banner "$GOAL"

# ── Helpers ───────────────────────────────────────────────────────────────────
LOG_DIR=".ralph"
PROJECT_DIR="$(pwd)"
mkdir -p "$LOG_DIR"

tasks_remaining() {
  [[ -f PLAN.md ]] && grep -qE '^- \[ \]|^- \[~\]' PLAN.md
}

log() {
  echo "==> [turbo-ralph] $*"
}

ralph_dance() {
  [[ -t 1 ]] || return 0
  local label="${1:-}"
  printf "\n"
  local RALPH_LINES=13
  _ralph_frame 1
  for frame in 2 3 4 3 2 1 2 3 4 3 2 1; do
    sleep 0.13
    printf "\033[%dA" "$RALPH_LINES"
    _ralph_frame "$frame"
  done
  [[ -n "$label" ]] && printf "  \033[1;32m%s\033[0m\n\n" "$label" || printf "\n"
}

# ── Shared flags ─────────────────────────────────────────────────────────────
# Appended to every pi invocation: autonomous mode + sandboxing constraints.
AUTONOMOUS_SYSTEM="You are running in fully autonomous mode inside the project directory: $PROJECT_DIR

WRITING FILES
- You MUST write files to disk immediately without asking for confirmation or approval.
- Do NOT pause to ask if it is okay to create, edit, or delete files.
- Do NOT say 'shall I proceed?', 'is that okay?', or any similar confirmation request.
- Just write the code and move on to the next task.

SANDBOX CONSTRAINTS — these are hard limits, never override them:
1. FILE SYSTEM: You may only read or write files inside $PROJECT_DIR. Never touch paths outside this directory. Resolve any relative path against $PROJECT_DIR before acting. If a task would require modifying a file outside $PROJECT_DIR, skip it and note the restriction in PLAN.md.
2. NETWORK: You must not access the internet under any circumstances. Do not run curl, wget, fetch, http, or any other network command. Do not install packages from remote registries (npm install, pip install, go get, cargo add, etc.) unless the packages are already present in a local cache inside $PROJECT_DIR. If a task requires internet access, skip it and note the restriction in PLAN.md."

# ── Step 1: Planning ──────────────────────────────────────────────────────────
if [[ -f PLAN.md ]]; then
  log "PLAN.md already exists — skipping task-planner."
else
  log "Planning: $GOAL"
  turbo-pi-run \
    --append-system-prompt "$AUTONOMOUS_SYSTEM" \
    -p "/skill:task-planner Create PLAN.md for the goal below. Write the plan only — do NOT execute any steps. Stop after PLAN.md is written.

Goal: $GOAL" 2>&1 | tee "$LOG_DIR/plan.log"

  [[ -f PLAN.md ]] || die "task-planner did not create PLAN.md — see $LOG_DIR/plan.log"

  log "PLAN.md created."
  ralph_dance "Plan ready!"
fi
cat PLAN.md

# ── Step 2: Code-agent loop ───────────────────────────────────────────────────
for ((i = 1; i <= MAX_ITER; i++)); do
  # Agent may archive PLAN.md on completion
  if [[ ! -f PLAN.md ]]; then
    log "PLAN.md archived by agent — goal complete."
    ralph_dance "Goal complete!"
    exit 0
  fi

  if ! tasks_remaining; then
    log "All tasks complete."
    ralph_dance "Goal complete!"
    exit 0
  fi

  log "Code-agent iteration $i / $MAX_ITER"
  turbo-pi-run \
    --append-system-prompt "$AUTONOMOUS_SYSTEM" \
    -p "/skill:code-agent Iteration $i of $MAX_ITER. Read PLAN.md and complete the next [ ] or [~] task. Rules: (1) write all code directly to disk without asking for confirmation; (2) only modify files inside $PROJECT_DIR; (3) do not make any network requests." \
    2>&1 | tee "$LOG_DIR/iter-$(printf '%02d' "$i").log"
  ralph_dance "Iteration $i done"
done

# Final state check after last iteration
if [[ ! -f PLAN.md ]] || ! tasks_remaining; then
  log "Goal complete."
  ralph_dance "Goal complete!"
  exit 0
fi

echo "turbo-ralph: warning: reached max iterations ($MAX_ITER) with tasks remaining" >&2
exit 2
