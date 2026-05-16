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
#   3   Iteration produced no code — stalled, Ralph is sad
#
# CONTACT
#   Jacob Andresen <jacob.andresen@gmail.com>

set -euo pipefail

MAX_ITER=10
# Resolved after GOAL is parsed so complexity detection can influence defaults.
# "auto" = scale by goal complexity (set below); explicit value skips auto-scaling.
PLANNER_TIMEOUT="${PLANNER_TIMEOUT:-auto}"
# RALPH_THINKING overrides both phases if set; phase-specific vars take precedence.
RALPH_THINKING="${RALPH_THINKING:-}"
# Deferred: resolved after argument parsing once GOAL is known.
RALPH_PLANNER_THINKING="${RALPH_PLANNER_THINKING:-}"
RALPH_WRITE_THINKING="${RALPH_WRITE_THINKING:-}"
GOAL=""
TARGET_DIR=""
FORCE=0

# ── Banner ────────────────────────────────────────────────────────────────────

print_banner() {
  local G='\033[0;32m' R='\033[0m'
  printf "\n  TURBO RALPH\n"
  [[ -n "${1:-}" ]] && printf "  ${G}goal:${R} %s\n" "$1"
  printf "\n"
  print_ralph_quote
}

print_ralph_quote() {
  local Q='\033[3;33m' # italic yellow — quote
  local E='\033[90m'   # dim grey     — episode
  local R='\033[0m'

  # mapfile requires bash 4+; use while-read for bash 3.2 (macOS default)
  local _ralph_quotes=() _rline
  while IFS= read -r _rline; do
    [[ -n "$_rline" ]] && _ralph_quotes+=("$_rline")
  done <<'RALPH_QUOTES'
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
  -d | --dir)
    [[ -n "${2-}" ]] || die "--dir requires a path"
    TARGET_DIR="$2"
    shift 2
    ;;
  -n | --max-iterations)
    [[ "${2-}" =~ ^[0-9]+$ ]] || die "--max-iterations requires a positive integer"
    MAX_ITER="$2"
    shift 2
    ;;
  --force)
    FORCE=1
    shift
    ;;
  -h | --help)
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

[[ -n "$GOAL" ]] || {
  echo "turbo-ralph: error: project goal is required" >&2
  usage 1
}

# ── Auto-tune by goal complexity ──────────────────────────────────────────────
# Runs after GOAL is known. Detects complexity to set smart defaults for
# planner timeout and write-phase thinking. Explicit env vars always win.
{
  _wc=$(printf '%s' "$GOAL" | wc -w | tr -d ' ')
  _has_lib=0
  printf '%s' "$GOAL" | grep -qiE \
    'SDL2|OpenGL|ncurses|dotnet|C#|csharp|tensorflow|pytorch|django|flask|opencv|wxwidgets' \
    && _has_lib=1

  # Trivial: ≤4 words, no external library (single-file programs like helloworld)
  # Simple:  ≤8 words, no external library (fibonacci, basic sqlite3)
  # Complex: longer or requires an external library (SDL2, C#, etc.)
  if   (( _has_lib || _wc > 8 )); then _complexity=complex
  elif (( _wc <= 4 ));             then _complexity=trivial
  else                                  _complexity=simple
  fi

  # Planner always needs at least medium thinking on qwen3:8b to reliably call Write.
  # The complexity heuristic only scales down the writer (shorter, more directive prompt).
  case "$_complexity" in
    trivial) _auto_planner=medium _auto_writer=off  _auto_combined=1 ;;
    simple)  _auto_planner=medium _auto_writer=off  _auto_combined=0 ;;
    complex) _auto_planner=medium _auto_writer=low  _auto_combined=0 ;;
  esac

  RALPH_PLANNER_THINKING="${RALPH_PLANNER_THINKING:-${RALPH_THINKING:-$_auto_planner}}"
  RALPH_WRITE_THINKING="${RALPH_WRITE_THINKING:-${RALPH_THINKING:-$_auto_writer}}"

  # Scale PLANNER_TIMEOUT by complexity when the user hasn't set it explicitly.
  # Trivial goals fail fast if the model stalls; complex goals get the full window.
  if [[ "$PLANNER_TIMEOUT" == "auto" ]]; then
    case "$_complexity" in
      trivial) PLANNER_TIMEOUT=240  ;;
      simple)  PLANNER_TIMEOUT=400  ;;
      complex) PLANNER_TIMEOUT=600  ;;
    esac
  fi

  # Combined plan+write: single pi session for trivially simple single-file goals.
  # Saves one pi startup + Ollama API round-trip. Falls back to normal write loop
  # if the combined call only writes PLAN.md (model stops after the first Write).
  RALPH_COMBINED="${RALPH_COMBINED:-$_auto_combined}"
}

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
  ((FORCE)) && return 0

  local file_count=0 git_commits=0
  file_count=$(find . -maxdepth 1 ! -name '.' ! -name '.*' | wc -l)
  if git rev-parse --git-dir &>/dev/null; then
    git_commits=$(git rev-list --count HEAD 2>/dev/null || echo 0)
  fi

  if ((file_count > 5 || git_commits > 0)); then
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
SESSION_DIR="$LOG_DIR/code-session"
mkdir -p "$LOG_DIR"

# ── Session archive ───────────────────────────────────────────────────────────
# Each run is archived to RALPH_ARCHIVE_DIR for analytical purposes.
# Prune ~/.ralph/sessions/ periodically to manage disk usage.
RALPH_ARCHIVE_DIR="${RALPH_ARCHIVE_DIR:-$HOME/.ralph/sessions}"
SESSION_ID="$(date +%Y%m%d-%H%M%S)-$(printf '%s' "$GOAL" | tr ' /' '_-' | tr -cd 'A-Za-z0-9_-' | cut -c1-40)"
SESSION_ARCHIVE_PATH="$RALPH_ARCHIVE_DIR/$SESSION_ID"
SESSION_START_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SESSION_START_EPOCH="$(date +%s)"

# Write a partial tombstone immediately — survives SIGKILL since EXIT trap won't run.
# _archive_finalize overwrites this with the full record on clean exit.
mkdir -p "$SESSION_ARCHIVE_PATH"
printf '{"session_id":"%s","goal":"%s","outcome":"unknown","exit_code":-1}\n' \
  "$SESSION_ID" "$GOAL" > "$SESSION_ARCHIVE_PATH/meta.json" 2>/dev/null || true

_archive_finalize() {
  local ec=$?
  set +e
  mkdir -p "$SESSION_ARCHIVE_PATH/logs" \
    || printf '[archive] WARNING: could not create logs dir\n' >&2
  [[ -d "$LOG_DIR" ]] && cp -r "$LOG_DIR/." "$SESSION_ARCHIVE_PATH/logs/" 2>/dev/null \
    || printf '[archive] WARNING: could not copy logs\n' >&2

  local tasks_total tasks_done
  tasks_total=$(grep -cE '^- \[[ x~]\]' PLAN.md 2>/dev/null || echo 0)
  tasks_done=$(grep -cE '^- \[x\]' PLAN.md 2>/dev/null || echo 0)
  [[ -f PLAN.md ]] && cp PLAN.md "$SESSION_ARCHIVE_PATH/PLAN-final.md" 2>/dev/null

  local outcome
  case "$ec" in
    0) outcome="success" ;;
    1) outcome="error" ;;
    2) outcome="max_iterations" ;;
    3) outcome="stalled" ;;
    *) outcome="unknown" ;;
  esac

  local end_ts duration
  end_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  duration=$(( $(date +%s) - SESSION_START_EPOCH ))

  # Write minimal tombstone first — survives a SIGKILL of the python3 call below.
  printf '{"session_id":"%s","goal":"%s","outcome":"%s","exit_code":%d}\n' \
    "$SESSION_ID" "$GOAL" "$outcome" "$ec" \
    > "$SESSION_ARCHIVE_PATH/meta.json" 2>/dev/null

  # Upgrade to full JSON. Use a temp file so a python3 failure doesn't truncate
  # the tombstone we just wrote.
  local _meta_tmp
  _meta_tmp="$(mktemp)"
  if python3 -c "
import json, sys
data = {
    'session_id': sys.argv[1],
    'goal': sys.argv[2],
    'project_dir': sys.argv[3],
    'start_time': sys.argv[4],
    'end_time': sys.argv[5],
    'duration_seconds': int(sys.argv[6]),
    'max_iterations': int(sys.argv[7]),
    'outcome': sys.argv[8],
    'exit_code': int(sys.argv[9]),
    'tasks_total': int(sys.argv[10]),
    'tasks_done': int(sys.argv[11]),
}
print(json.dumps(data, indent=2))
" "$SESSION_ID" "$GOAL" "$PROJECT_DIR" "$SESSION_START_TS" "$end_ts" \
  "$duration" "$MAX_ITER" "$outcome" "$ec" "$tasks_total" "$tasks_done" \
  > "$_meta_tmp" 2>/dev/null && [[ -s "$_meta_tmp" ]]; then
    mv "$_meta_tmp" "$SESSION_ARCHIVE_PATH/meta.json"
  else
    rm -f "$_meta_tmp"
  fi

  log "Session archived → $SESSION_ARCHIVE_PATH"
}

trap _archive_finalize EXIT

tasks_remaining() {
  [[ -f PLAN.md ]] && grep -qE '^- \[ \]|^- \[~\]' PLAN.md
}

# Extract the test command from PLAN.md's '## Test Command' section.
# Looks for the first non-empty line — fenced code blocks and inline code are unwrapped.
test_command() {
  [[ -f PLAN.md ]] || return 1
  awk '
    /^##[[:space:]]+Test Command[[:space:]]*$/ { in_sec = 1; next }
    in_sec && /^##[[:space:]]/ { exit }
    in_sec {
      line = $0
      sub(/^[[:space:]]*```[a-zA-Z]*[[:space:]]*$/, "", line)
      sub(/^[[:space:]]*`/, "", line); sub(/`[[:space:]]*$/, "", line)
      sub(/^[[:space:]]+/, "", line); sub(/[[:space:]]+$/, "", line)
      if (line != "") { print line; exit }
    }
  ' PLAN.md
}

# Run the test command if PLAN.md declares one. Returns 0 if tests pass or no
# command is declared; non-zero if tests fail. $1 = label used in log filename.
run_tests() {
  local cmd label="${1:-run}"
  cmd="$(test_command)"
  if [[ -z "$cmd" ]]; then
    log "No '## Test Command' in PLAN.md — skipping test gate."
    return 0
  fi
  log "Running tests: $cmd"
  bash -c "$cmd" 2>&1 | tee "$LOG_DIR/tests-$label.log"
  return "${PIPESTATUS[0]}"
}

log() {
  echo "==> [turbo-ralph] $*"
}

ralph_dance() {
  local label="${1:-}"
  [[ -n "$label" ]] && printf "\n  \033[1;32m%s\033[0m\n\n" "$label"
}

ralph_sad() {
  local label="${1:-No code was written.}"
  printf "\n  \033[1;31m%s\033[0m\n\n" "$label"
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
1. NETWORK: Do not run arbitrary network commands (curl, wget, fetch, http, etc.) for general internet access.
2. EXTERNAL LIBRARIES / PACKAGES: You MAY install and use external libraries, modules, or packages (via npm install, pip install, go get, cargo add, etc.) ONLY IF they are explicitly listed in PLAN.md. Do not pull in dependencies that PLAN.md does not mention. If you need a dependency that is not listed, add it to PLAN.md first, then install it."

# ── Step 1: Planning ──────────────────────────────────────────────────────────

# Draw a single-line progress bar on stdout (overwrites the current line).
# Usage: _planner_progress ELAPSED TIMEOUT
_planner_progress() {
  local elapsed=$1 timeout=$2 width=40
  local pct filled bar j
  pct=$(( elapsed * 100 / timeout ))
  filled=$(( elapsed * width / timeout ))
  bar=""
  for ((j = 0; j < filled; j++)); do bar+="="; done
  if (( filled < width )); then
    bar+=">"
    for ((j = filled + 1; j < width; j++)); do bar+=" "; done
  fi
  printf "\r  \033[36mPlanning\033[0m [%s] %3d%%  %ds / %ds" \
    "$bar" "$pct" "$elapsed" "$timeout"
}

_run_planner() {
  # $1 = log file.
  # Runs pi in a background subshell and polls every 2 s for PLAN.md.
  # Kills the planner the moment PLAN.md is written so we don't wait for
  # the model to finish its post-Write rambling. Falls back to a hard
  # kill after PLANNER_TIMEOUT seconds regardless.
  local plan_log="$1"
  ( turbo-pi-run \
    --thinking "$RALPH_PLANNER_THINKING" \
    --append-system-prompt "$AUTONOMOUS_SYSTEM" \
    -p "Your only output must be one Write tool call that creates '$PROJECT_DIR/PLAN.md'. No chat text, no fenced code blocks.

REQUIREMENTS:

1. PLAN.md must contain a '## Files' section: a flat ordered list of files to create, one per line,
   in dependency order (dependencies before dependents).
   Each line: '- [ ] relative/path/to/file' optionally followed by ' — one-line description'.

   USE THE SIMPLEST STRUCTURE THAT FITS THE GOAL.

   TRIVIAL programs (single-function utilities, tiny scripts — anything that fits
   naturally in one source file): use exactly ONE file, no Makefile, no modules, no headers.
   Compile and run inline in the Test Command.

   Example (a Fahrenheit-to-Celsius converter):

     ## Files
     - [ ] main.c — temperature converter

     ## Test Command
     gcc main.c -o convert && ./convert 212 | grep -q \"100\"

   NON-TRIVIAL programs (multiple genuinely distinct components, reusable libraries, command-line
   tools with options, programs that use external libraries like SDL2/OpenGL/etc.): use a Makefile.

   Example (a 2-D physics simulation with a pure-logic library):

     ## Files
     - [ ] Makefile — build rules (must include ALL targets referenced by Test Command)
     - [ ] src/physics.c — physics logic
     - [ ] include/physics.h — physics interface
     - [ ] tests/test_physics.c — unit tests for physics
     - [ ] src/main.c — entry point

     ## Test Command
     make check

   INTERACTIVE / GRAPHICAL programs (SDL2, OpenGL, ncurses, games, anything that opens
   a window or reads from stdin in a loop) MUST NOT have unit test files.
   The only test for these programs is a build smoke test — does it compile cleanly?

   Example (an SDL2 renderer):

     ## Files
     - [ ] Makefile — build rules
     - [ ] src/main.c — SDL2 renderer

     ## Test Command
     make

   IMPORTANT: the examples above are structural templates only. Every file path, description,
   compiler flag, and test assertion must be derived from the actual GOAL, not from the example.

2. LANGUAGE RULE: Use the exact language stated in the GOAL.
   - 'C' or 'using C' → .c files compiled with gcc/clang. NEVER use C# (.cs / dotnet).
   - 'C++' or 'using C++' → .cpp files compiled with g++/clang++.
   - 'Python' → .py files. 'Go' → .go files. 'Rust' → .rs files. Etc.
   When in doubt, prefer the simpler systems language (C, not C++; Python, not Ruby).

3. MAKEFILE COMPLETENESS: If the Test Command references a make target (e.g., 'make check',
   'make test'), the Makefile MUST define that target from the start. The Makefile is written
   first; it cannot be updated later. Define test targets with a recipe even if the test
   source file does not exist yet — e.g.:
     check: tests/test_foo
         ./tests/test_foo
     tests/test_foo: tests/test_foo.c
         \$(CC) \$(CFLAGS) tests/test_foo.c -o tests/test_foo

4. Module functions should return values rather than printing so they can be unit-tested.
   Exception: interactive or graphical programs — use a build-only smoke test.

5. Include '## Test Command' with a single shell command that exits non-zero on failure.
   All paths must be project-relative, not absolute.

6. Include '## Dependencies' listing the compiler and any required tools.

7. Plan only — do not implement. Write PLAN.md and stop.

GOAL: $GOAL" 2>&1 | tee "$plan_log" ) &
  local _bg=$!

  local _elapsed=0
  while kill -0 "$_bg" 2>/dev/null; do
    _planner_progress "$_elapsed" "$PLANNER_TIMEOUT"
    if [[ -f PLAN.md ]]; then
      printf "\r\033[K"
      log "PLAN.md written — stopping planner early (${_elapsed}s elapsed)."
      pkill -TERM -P "$_bg" 2>/dev/null || true
      kill "$_bg" 2>/dev/null || true
      wait "$_bg" 2>/dev/null || true
      return 0
    fi
    if (( _elapsed >= PLANNER_TIMEOUT )); then
      printf "\r\033[K"
      log "Planner timed out after ${PLANNER_TIMEOUT}s — killing."
      local _suggested=$(( PLANNER_TIMEOUT + 300 ))
      printf "  \033[33mSuggestion:\033[0m xhigh thinking may need more time. Re-run with a larger timeout:\n"
      printf "              PLANNER_TIMEOUT=%d turbo-ralph.sh \"%s\"\n" "$_suggested" "$GOAL"
      pkill -TERM -P "$_bg" 2>/dev/null || true
      kill "$_bg" 2>/dev/null || true
      wait "$_bg" 2>/dev/null || true
      return 1
    fi
    sleep 2
    (( _elapsed += 2 ))
  done
  printf "\r\033[K"
  wait "$_bg"
}

# Combined planner+writer: single pi session that writes PLAN.md then the source file.
# Used for trivially simple single-file goals to save one pi startup round-trip.
# Sets RALPH_COMBINED_SRC_FILE on success so the write loop can skip that file.
RALPH_COMBINED_SRC_FILE=""
_run_combined_planner_writer() {
  local plan_log="$1"
  local _combined_prompt
  _combined_prompt="Write TWO files in sequence using the Write tool.

STEP 1 — Write '$PROJECT_DIR/PLAN.md' with:

## Files
- [ ] <filename> — <one-line description>

## Test Command
<single command that exits non-zero on failure, no Makefile>

## Dependencies
<required tools>

Pick the simplest filename (main.c, main.py, etc.). Inline compilation in Test Command.

STEP 2 — Immediately after writing PLAN.md, write the source file listed in it.

Do not pause between steps. Write both files and then STOP. No explanations.

GOAL: $GOAL"

  ( turbo-pi-run \
    --thinking "$RALPH_PLANNER_THINKING" \
    --append-system-prompt "$AUTONOMOUS_SYSTEM" \
    -p "$_combined_prompt" \
    < /dev/null \
    2>&1 | tee "$plan_log" ) &
  local _bg=$!

  local _elapsed=0 _src_file=""
  while kill -0 "$_bg" 2>/dev/null; do
    _planner_progress "$_elapsed" "$PLANNER_TIMEOUT"

    # Once PLAN.md appears, grab the source file path to watch for.
    # Re-check each tick until we get a non-empty task line (guards against partial writes).
    if [[ -z "$_src_file" && -f PLAN.md ]]; then
      local _task_line
      _task_line="$(grep -m1 -E '^- \[ \]' PLAN.md 2>/dev/null || true)"
      if [[ -n "$_task_line" ]]; then
        _src_file="$(printf '%s\n' "$_task_line" | sed 's/^- \[[ x~]\] //' | awk '{print $1}')"
        log "Combined: PLAN.md ready — watching for source file: $_src_file"
      fi
    fi

    # Both files written — kill pi and report success.
    if [[ -n "$_src_file" && -f "$_src_file" ]]; then
      printf "\r\033[K"
      log "Combined: PLAN.md + $_src_file written in ${_elapsed}s."
      pkill -TERM -P "$_bg" 2>/dev/null || true
      kill "$_bg" 2>/dev/null || true
      wait "$_bg" 2>/dev/null || true
      RALPH_COMBINED_SRC_FILE="$_src_file"
      return 0
    fi

    if (( _elapsed >= PLANNER_TIMEOUT )); then
      printf "\r\033[K"
      log "Combined planner+writer timed out after ${PLANNER_TIMEOUT}s."
      pkill -TERM -P "$_bg" 2>/dev/null || true
      kill "$_bg" 2>/dev/null || true
      wait "$_bg" 2>/dev/null || true
      return 1
    fi
    sleep 2
    (( _elapsed += 2 ))
  done
  printf "\r\033[K"
  wait "$_bg"
}

# Recover PLAN.md when the planner emitted it as a fenced ```markdown block
# in chat instead of invoking the Write tool.
_recover_plan_from_log() {
  local plan_log="$1"
  [[ -s "$plan_log" ]] || return 1
  awk '
    /^[[:space:]]*```([Mm]arkdown|md)?[[:space:]]*$/ {
      if (!in_block) { in_block = 1; next }
    }
    /^[[:space:]]*```[[:space:]]*$/ {
      if (in_block) { exit }
    }
    in_block { print }
  ' "$plan_log" > PLAN.md.recovered

  if [[ -s PLAN.md.recovered ]]; then
    mv PLAN.md.recovered PLAN.md
    log "Recovered PLAN.md from fenced block in $plan_log (planner did not call Write)."
    return 0
  fi
  rm -f PLAN.md.recovered
  return 1
}

# When the model writes code as chat text instead of calling Write, extract
# the first fenced code block from the log and save it to the target path.
_recover_file_from_log() {
  local log_file="$1" target="$2"
  [[ -s "$log_file" ]] || return 1
  local dir
  dir="$(dirname "$target")"
  [[ "$dir" != "." ]] && mkdir -p "$dir"
  awk '
    /^[[:space:]]*```[a-zA-Z]*[[:space:]]*$/ {
      if (!in_block) { in_block = 1; next }
    }
    /^[[:space:]]*```[[:space:]]*$/ {
      if (in_block) { exit }
    }
    in_block { print }
  ' "$log_file" > "$target.recovered"
  if [[ -s "$target.recovered" ]]; then
    mv "$target.recovered" "$target"
    log "Recovered $target from fenced block in $log_file (model did not call Write)."
    return 0
  fi
  rm -f "$target.recovered"
  return 1
}

if [[ -f PLAN.md ]]; then
  log "PLAN.md already exists — skipping task-planner."
  grep -qE '^### Group ' PLAN.md \
    && die "PLAN.md uses old '### Group N' format — delete it to re-plan with the new flat '## Files' format."
  grep -qE '^- \[ \]|^- \[~\]|^- \[x\]' PLAN.md \
    || die "Existing PLAN.md has no task checklist — delete it to re-plan."
  grep -qiE '^- \[[ x~]\].*\btest' PLAN.md \
    || log "WARNING: existing PLAN.md has no unit-test file — consider deleting to re-plan."
  grep -qiE '^- \[[ x~]\].*(Makefile|CMakeLists|setup\.py|package\.json|build\.sh|Cargo\.toml)' PLAN.md \
    || log "NOTE: existing PLAN.md has no build-system file — OK for trivial single-file programs."
else
  MAX_PLAN_ATTEMPTS=2
  for ((attempt = 1; attempt <= MAX_PLAN_ATTEMPTS; attempt++)); do
    if ((attempt == 1)); then
      log "Planning: $GOAL (planner=$RALPH_PLANNER_THINKING writer=$RALPH_WRITE_THINKING timeout=${PLANNER_TIMEOUT}s complexity=${_complexity:-?})"
      plan_log="$LOG_DIR/plan.log"
    else
      log "Planner attempt $attempt / $MAX_PLAN_ATTEMPTS (previous attempt produced no PLAN.md)"
      plan_log="$LOG_DIR/plan-attempt-$(printf '%02d' "$attempt").log"
    fi

    if ((RALPH_COMBINED)) && ((attempt == 1)); then
      log "Using combined plan+write mode (single pi session)."
      _run_combined_planner_writer "$plan_log" || true
    else
      _run_planner "$plan_log" < /dev/null
    fi
    plan_ec=$?
    plan_bytes=$(wc -c <"$plan_log" 2>/dev/null || echo 0)
    log "Planner exited $plan_ec, captured $plan_bytes bytes of output."

    [[ -f PLAN.md ]] || _recover_plan_from_log "$plan_log" || true
    [[ -f PLAN.md ]] && break

    log "Attempt $attempt: no PLAN.md produced (pi exit=$plan_ec, log=$plan_bytes bytes)."
  done

  if [[ ! -f PLAN.md ]]; then
    die "task-planner did not create PLAN.md after $MAX_PLAN_ATTEMPTS attempts — see $LOG_DIR/plan*.log (last pi exit=$plan_ec, last log=$plan_bytes bytes)"
  fi
  grep -qE '^- \[ \]|^- \[~\]|^- \[x\]' PLAN.md || die "PLAN.md has no task checklist — see $LOG_DIR/plan.log"
  grep -qiE '^- \[[ x~]\].*\btest' PLAN.md \
    || log "WARNING: PLAN.md has no test file — acceptable for trivial I/O programs (see $LOG_DIR/plan.log)"
  grep -qiE '^- \[[ x~]\].*(Makefile|CMakeLists|setup\.py|package\.json|build\.sh|Cargo\.toml)' PLAN.md \
    || log "NOTE: PLAN.md has no build-system file — OK for trivial single-file programs."

  log "PLAN.md created."
  ralph_dance "Plan ready!"
  cat PLAN.md
fi

# ── PLAN.md integrity checks ──────────────────────────────────────────────────

# Strip Ollama thinking-mode tokens (/think, <think>, </think>, <thinking>,
# </thinking>) that sometimes leak into model output and corrupt the plan.
_strip_thinking_artifacts() {
  local tmp
  tmp="$(mktemp)"
  sed -E 's|[[:space:]]?/think[[:space:]]?||g; s|[[:space:]]?</?think(ing)?>[[:space:]]?||g' \
    PLAN.md > "$tmp"
  if ! diff -q PLAN.md "$tmp" > /dev/null 2>&1; then
    log "WARNING: thinking artifact tokens stripped from PLAN.md"
    mv "$tmp" PLAN.md
  else
    rm -f "$tmp"
  fi
}

# Check that key words from the goal appear somewhere in PLAN.md.
# Emits a warning (not a hard failure) so the session can proceed while still
# surfacing misaligned plans. Words shorter than 4 chars and common stopwords
# are skipped. Returns 1 if no goal words were found at all.
_check_plan_goal_alignment() {
  local plan_text
  plan_text="$(tr '[:upper:]' '[:lower:]' < PLAN.md)"
  local goal_lower
  goal_lower="$(printf '%s' "$GOAL" | tr '[:upper:]' '[:lower:]')"

  local stopwords="and the via with for from that this are not make"
  local found=0 missing=()

  while IFS= read -r word; do
    [[ ${#word} -lt 4 ]] && continue
    local stop=0
    for s in $stopwords; do [[ "$word" == "$s" ]] && stop=1 && break; done
    ((stop)) && continue
    if printf '%s' "$plan_text" | grep -qF "$word"; then
      found=1
    else
      missing+=("$word")
    fi
  done < <(printf '%s' "$goal_lower" | tr -cs 'a-z0-9' '\n')

  if (( found == 0 )); then
    log "WARNING: PLAN.md contains none of the goal keywords — plan may be misaligned."
    log "  Goal: $GOAL"
    log "  Missing terms: ${missing[*]:-<none>}"
    return 1
  fi
  if (( ${#missing[@]} > 0 )); then
    log "NOTE: PLAN.md is missing some goal terms: ${missing[*]} (may be acceptable)"
  fi

  # Check for common language-name mismatches that the keyword filter misses
  # because the language name is ≤3 chars (C, Go) or easily confused (C vs C#).
  local plan_files
  plan_files="$(grep -iE '^- \[[ x~]\]' PLAN.md | awk '{print $3}' | tr '\n' ' ')"
  if printf '%s' "$goal_lower" | grep -qwE '\bc\b' && \
     ! printf '%s' "$goal_lower" | grep -qwE 'c\+\+|c#|csharp'; then
    if printf '%s' "$plan_files" | grep -qE '\.cs\b'; then
      log "WARNING: goal says 'C' but PLAN.md contains .cs (C#) files — plan likely misidentified the language."
      return 1
    fi
  fi
  if printf '%s' "$goal_lower" | grep -qwE '\bgo\b'; then
    if printf '%s' "$plan_files" | grep -qvE '\.go\b'; then
      log "NOTE: goal mentions 'go' but PLAN.md has no .go files — verify language choice."
    fi
  fi

  return 0
}

_strip_thinking_artifacts
_check_plan_goal_alignment || log "Proceeding despite alignment warning — check PLAN.md before continuing."

# Snapshot the initial PLAN.md for before/after analysis
mkdir -p "$SESSION_ARCHIVE_PATH"
cp PLAN.md "$SESSION_ARCHIVE_PATH/PLAN-initial.md" 2>/dev/null || true

# ── Step 2: Helpers ───────────────────────────────────────────────────────────

next_task() {
  [[ -f PLAN.md ]] && grep -m1 -E '^- \[ \]' PLAN.md || true
}

# "- [ ] src/hello.c — description" → "src/hello.c"
task_file_path() {
  printf '%s\n' "$1" | sed 's/^- \[[ x~]\] //' | awk '{print $1}'
}

# "- [ ] src/hello.c — description" → "description" (empty if none)
task_description() {
  local stripped
  stripped="$(printf '%s\n' "$1" | sed 's/^- \[[ x~]\] //')"
  printf '%s\n' "$stripped" \
    | awk 'NF>1{$1=""; print substr($0,2)}' \
    | sed 's/^[[:space:]]*[—–-][[:space:]]*//' \
    | grep -v '^$' || true
}

is_test_file() {
  local f
  f="$(basename "$1")"
  [[ "$1" == tests/* || "$1" == test/* || "$f" == test_* || "$f" == *_test.* ]]
}

# Mark the first unchecked task matching task_file done in PLAN.md.
mark_task_done() {
  local task_file="$1"
  local tmp
  tmp="$(mktemp)"
  awk -v f="$task_file" '
    !done && /^- \[ \] / {
      rest = substr($0, 7)
      if (substr(rest, 1, length(f)) == f &&
          (length(rest) == length(f) || substr(rest, length(f)+1, 1) ~ /[ \t]/)) {
        print "- [x] " rest; done=1; next
      }
    }
    { print }
  ' PLAN.md > "$tmp" && mv "$tmp" PLAN.md
}

# ── Step 3: Code-agent loop ───────────────────────────────────────────────────
# One pi call per file. The orchestrator runs tests and marks tasks done — the
# model's only job is to write the file it is given.

WRITE_RULES="1. Call Write ONCE to create the file at the exact path given. Do not ask for confirmation.
2. Do not create any other files. Write exactly the one file you are asked to write.
3. Do not emit code in chat — only via the Write tool.
4. Infer all content from the project goal and PLAN.md. NEVER ask for clarification or request input — write your best implementation immediately, even for headers and interface files.
5. If writing a header or interface file, write a complete, reasonable declaration based on the goal. Never say 'please provide the content' — just write it.
6. After the Write call succeeds, STOP immediately. Do not explain, summarize, or add any chat text after writing."

# Return file contents for every already-completed task file, formatted as
# fenced code blocks. Empty output when no files are done yet.
_existing_files_context() {
  local out=""
  while IFS= read -r line; do
    local f
    f="$(task_file_path "$line")"
    [[ -f "$f" ]] || continue
    out+="### $f
\`\`\`
$(cat "$f")
\`\`\`

"
  done < <(grep -E '^- \[x\]' PLAN.md 2>/dev/null || true)
  printf '%s' "$out"
}

# Return the list of source files that still need to be written (pending tasks
# after the current one). Used to inject exact paths into Makefile prompts.
_pending_source_files() {
  local current="$1" found=0 out=""
  while IFS= read -r line; do
    local f
    f="$(task_file_path "$line")"
    if [[ "$f" == "$current" ]]; then found=1; continue; fi
    ((found)) && out+="  $f\n"
  done < <(grep -E '^- \[ \]' PLAN.md 2>/dev/null || true)
  printf '%b' "$out"
}

# True if $1 is a build/config file that needs exact source paths.
_is_build_file() {
  local base
  base="$(basename "$1")"
  [[ "$base" =~ ^(Makefile|CMakeLists\.txt|setup\.py|Cargo\.toml|build\.sh|package\.json|pyproject\.toml|meson\.build)$ ]]
}

# If combined mode already wrote the source file during planning, mark it done
# so the write loop below has no work to do.
if [[ -n "$RALPH_COMBINED_SRC_FILE" && -f "$RALPH_COMBINED_SRC_FILE" ]]; then
  log "Combined mode: $RALPH_COMBINED_SRC_FILE written during planning — marking done."
  mark_task_done "$RALPH_COMBINED_SRC_FILE"
  ralph_dance "Iteration 1 done (combined): $RALPH_COMBINED_SRC_FILE"
fi

for ((i = 1; i <= MAX_ITER; i++)); do
  task_line="$(next_task)"
  if [[ -z "$task_line" ]]; then
    log "All tasks complete."
    break
  fi

  task_file="$(task_file_path "$task_line")"
  task_desc="$(task_description "$task_line")"
  log "Iteration $i / $MAX_ITER: $task_file"

  iter_log="$LOG_DIR/iter-$(printf '%02d' "$i").log"
  iter_err_log="$LOG_DIR/iter-$(printf '%02d' "$i").err"

  _plan_content="$(cat PLAN.md)"
  _existing_ctx="$(_existing_files_context)"

  write_prompt="PROJECT GOAL: $GOAL

=== PLAN.md (context only — do not rewrite) ===
$_plan_content
=== END PLAN.md ==="

  if [[ -n "$_existing_ctx" ]]; then
    write_prompt+="

=== Already-written files (for reference) ===
$_existing_ctx=== END ==="
  fi

  write_prompt+="

TASK: Write the file: $task_file${task_desc:+
Description: $task_desc}"

  # Inject exact source-file paths when writing a build file so the model
  # uses PLAN.md paths rather than guessing or simplifying them.
  if _is_build_file "$task_file"; then
    _pending="$(_pending_source_files "$task_file")"
    if [[ -n "$_pending" ]]; then
      write_prompt+="

CRITICAL — FILE PATHS: The following source files will be created at these EXACT paths (taken from PLAN.md). Your $task_file MUST reference them at these exact paths — do NOT simplify, flatten, or alter any path:
$_pending"
    fi
  fi

  write_prompt+="

Do not create any other files. Do not run tests. Do not modify PLAN.md."

  # Fresh session per write call — small models do not need cross-call context
  # since the orchestrator owns state tracking.
  turbo-pi-run \
    --thinking "$RALPH_WRITE_THINKING" \
    --session-dir "$SESSION_DIR" \
    --append-system-prompt "$AUTONOMOUS_SYSTEM" \
    --append-system-prompt "$WRITE_RULES" \
    -p "$write_prompt" \
    < /dev/null \
    2> >(tee "$iter_err_log" >&2) | tee "$iter_log"

  # Detect autonomy violations: model asked a question instead of writing.
  # Retry once with an explicit scolding before giving up.
  if [[ ! -f "$task_file" ]]; then
    _stall_phrases="could you please|please provide|please tell|what content|shall I|should I write|what would you like|can you provide"
    _stall_log=""
    if grep -qiE "$_stall_phrases" "$iter_log" 2>/dev/null; then
      log "Model violated autonomy rules (asked a question). Retrying with corrective prompt."
      _stall_log="$LOG_DIR/iter-$(printf '%02d' "$i")-stall-retry.log"
      turbo-pi-run \
        --thinking "$RALPH_WRITE_THINKING" \
        --session-dir "$SESSION_DIR" \
        --append-system-prompt "$AUTONOMOUS_SYSTEM" \
        --append-system-prompt "$WRITE_RULES" \
        -p "You asked a clarifying question instead of writing the file. That is not allowed.
Write the file NOW: $task_file
Derive every detail from the PROJECT GOAL and PLAN.md. Do not ask anything. Just write it." \
        < /dev/null \
        2>/dev/null | tee "$_stall_log"
    fi
    _recover_file_from_log "$iter_log" "$task_file" \
      || { [[ -n "$_stall_log" ]] && _recover_file_from_log "$_stall_log" "$task_file"; } \
      || {
        ralph_sad "Model did not write $task_file — stalled."
        log "Iteration $i: $task_file not found on disk after write call."
        exit 3
      }
  fi

  # Run tests after every test file. The orchestrator owns this check; the
  # model is not asked to run tests itself.
  _test_cmd="$(test_command)"
  if [[ -n "$_test_cmd" ]] && is_test_file "$task_file"; then
    _test_log="$LOG_DIR/tests-iter-$(printf '%02d' "$i").log"
    if ! bash -c "$_test_cmd" > "$_test_log" 2>&1; then
      log "Tests failing after $task_file — invoking repair agent."
      fix_rules="REPAIR RULES — follow exactly:
1. Call the Bash tool to run: $_test_cmd
2. Read the error output. Use Write to rewrite the entire broken file, or use Edit to fix a specific section. When using Edit, provide enough surrounding context (3-5 lines) to make the old_string unique in the file. Do NOT explain, do NOT show JSON examples, do NOT say 'here is how to fix it'. Just fix it using the tool.
3. Call Bash to run the test command again to confirm it passes.
4. Stop when the test command exits 0. Do not modify PLAN.md."
      fix_log="$LOG_DIR/fix-$(printf '%02d' "$i").log"
      test_tail="$(tail -80 "$_test_log")"
      turbo-pi-run \
        --thinking "$RALPH_WRITE_THINKING" \
        --session-dir "$SESSION_DIR" \
        --continue \
        --append-system-prompt "$AUTONOMOUS_SYSTEM" \
        --append-system-prompt "$fix_rules" \
        -p "Tests are failing. Use the Write or Edit tool to fix the broken file NOW. Do not explain how to fix it — just fix it.

Test command: \`$_test_cmd\`
Last output:
$test_tail" \
        < /dev/null \
        2>&1 | tee "$fix_log"

      # Detect explanation-mode: model described the fix in chat instead of calling tools.
      if grep -qiE '```json|"oldText"|"newText"|here is how|you can fix|to fix this' "$fix_log" 2>/dev/null \
          && ! bash -c "$_test_cmd" > "$_test_log" 2>&1; then
        log "Repair agent emitted explanations instead of calling Write/Edit tools."
      fi

      if ! bash -c "$_test_cmd" > "$_test_log" 2>&1; then
        ralph_sad "Tests still failing after repair — stalled."
        log "Tests failing after repair for $task_file."
        exit 3
      fi
    fi
  fi

  # After writing a build file, warn if it's missing planned source file paths.
  # This catches the common bug where the model uses 'main.c' instead of 'src/main.c'.
  if _is_build_file "$task_file"; then
    local _build_content _missing_paths=()
    _build_content="$(cat "$task_file" 2>/dev/null)"
    while IFS= read -r _pending_line; do
      local _pf
      _pf="$(task_file_path "$_pending_line")"
      # Skip other build files
      _is_build_file "$_pf" && continue
      local _pf_base
      _pf_base="$(basename "$_pf")"
      # Check if either the full path or just the basename appears in the build file.
      # A mismatch means the path is wrong (e.g. 'main.c' instead of 'src/main.c').
      if printf '%s' "$_build_content" | grep -qF "$_pf"; then
        : # exact path present — good
      elif printf '%s' "$_build_content" | grep -qF "$_pf_base"; then
        log "WARNING: $task_file references '$_pf_base' but PLAN.md lists '$_pf' — path mismatch may cause build failure."
        _missing_paths+=("$_pf")
      fi
    done < <(grep -E '^- \[ \]' PLAN.md 2>/dev/null || true)
    if [[ ${#_missing_paths[@]} -gt 0 ]]; then
      log "Build file path check: ${#_missing_paths[@]} path(s) may be wrong: ${_missing_paths[*]}"
    fi
  fi

  mark_task_done "$task_file"
  log "Marked done: $task_file"
  ralph_dance "Iteration $i done: $task_file"
done

# ── Final test gate ──────────────────────────────────────────────────────────
# Safety net: the orchestrator runs tests per-file, but this gate verifies the
# full suite passes once all files are written. Retries up to 3 times with a
# repair agent if needed.
_final_test_gate() {
  local cmd
  cmd="$(test_command)"
  [[ -z "$cmd" ]] && { log "No '## Test Command' in PLAN.md — skipping final test gate."; return 0; }

  local max_retries=3 attempt=0
  while ! run_tests "final"; do
    attempt=$((attempt + 1))
    if ((attempt > max_retries)); then
      ralph_sad "Tests still failing after $max_retries retries. Giving up."
      exit 3
    fi
    log "Final tests failed — repair retry $attempt / $max_retries"
    local retry_log="$LOG_DIR/final-retry-$(printf '%02d' "$attempt").log"
    local test_output
    test_output="$(tail -200 "$LOG_DIR/tests-final.log" 2>/dev/null || true)"
    turbo-pi-run \
      --thinking "$RALPH_WRITE_THINKING" \
      --session-dir "$SESSION_DIR" \
      --continue \
      --append-system-prompt "$AUTONOMOUS_SYSTEM" \
      -p "Tests are still failing. Use Write to rewrite the broken file (preferred), or use Edit with enough surrounding context (3-5 lines) to make old_string unique. Do NOT explain — call the tool directly.

Test command: \`$cmd\`
Last output:
$test_output" \
      < /dev/null \
      2>&1 | tee "$retry_log"

    # Detect explanation-mode failure before next loop iteration.
    if grep -qiE '```json|"oldText"|"newText"|here is how|you can fix|to fix this' "$retry_log" 2>/dev/null; then
      log "WARNING: repair agent (retry $attempt) emitted explanations instead of calling Write/Edit."
    fi
  done
}

if [[ ! -f PLAN.md ]] || ! tasks_remaining; then
  _final_test_gate
  log "Goal complete."
  ralph_dance "Goal complete!"
  exit 0
fi

echo "turbo-ralph: warning: reached max iterations ($MAX_ITER) with tasks remaining" >&2
exit 2
