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
_run_planner() {
  # $1 = log file. Returns pi's exit code.
  local plan_log="$1"
  turbo-pi-run \
    --append-system-prompt "$AUTONOMOUS_SYSTEM" \
    -p "/skill:task-planner

GOAL: $GOAL

HARD REQUIREMENTS — failing any of these means the task failed:

1. You MUST invoke the Write tool with file_path '$PROJECT_DIR/PLAN.md'. Emitting the plan as chat text or inside a fenced code block does NOT create the file and counts as failure.

2. Every task line in PLAN.md MUST start with literal '- [ ] '. Numbered lists ('1.', '2.', '- 1.', '* '), bullet lists without checkboxes, and bold/heading task lines are REJECTED by downstream tooling. Example of an acceptable line:
       - [ ] (group:1) create src/main.c with an empty main()
   Example of REJECTED lines:
       1. Create src/main.c
       - Create src/main.c
       **Create source file**: ...

3. Group independent tasks with '(group:N)' right after the checkbox: '- [ ] (group:1) ...'. Tasks in the same group must not depend on each other; later groups may depend on earlier ones. Untagged tasks become their own singleton group.

4. Dependencies: the plan may use (a) C/C++ libraries the coding agent already knows (libc, POSIX, libcurl, OpenSSL, SQLite, zlib, SDL2, Boost, etc.) and (b) common Linux CLI tools (make, cmake, gcc, clang, pkg-config, grep, sed, awk, jq, git). Do NOT use language-registry packages (npm, pip, cargo, go modules, etc.). List every dependency under a '## Dependencies' section by name.

5. TESTS PER STEP: every implementation task MUST be paired with a unit-test task in the SAME group. The test task line MUST mention 'unit test' or 'test' explicitly and reference what it covers. Include a top-level '## Test Command' section in PLAN.md that gives a single shell command which runs the entire UNIT TEST suite (e.g. 'make check', 'ctest --output-on-failure', './run-unit-tests.sh', 'pytest tests/'). The test command MUST exit non-zero on failure.

   CRITICAL — the '## Test Command' MUST execute unit tests ONLY. It MUST NOT run the main program / produced executable / application binary as part of the test command. Building the binary is fine (tests may link against it), but invoking it for an end-to-end smoke check is FORBIDDEN. Reason: the main program may take input, write to filesystem paths, open ports, or otherwise have side effects that are unsafe to run from a test harness. Unit tests must call individual functions/modules in isolation.

   ALL FILESYSTEM PATHS used by Makefiles, scripts, and tests MUST be relative to the project directory. Never write to absolute paths like '/my_program' or '/output' — these will be denied by the sandbox. Use './my_program', 'build/my_program', or similar.

   If a task has no testable behavior (e.g. 'create empty directory'), mark it '(no-test)' after the checkbox: '- [ ] (group:1) (no-test) ...'.

6. Plan only — do NOT implement. Do not ask for confirmation. Write PLAN.md and stop." 2>&1 | tee "$plan_log"
  return "${PIPESTATUS[0]}"
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

if [[ -f PLAN.md ]]; then
  log "PLAN.md already exists — skipping task-planner."
else
  MAX_PLAN_ATTEMPTS=2
  for ((attempt = 1; attempt <= MAX_PLAN_ATTEMPTS; attempt++)); do
    if ((attempt == 1)); then
      log "Planning: $GOAL"
      plan_log="$LOG_DIR/plan.log"
    else
      log "Planner attempt $attempt / $MAX_PLAN_ATTEMPTS (previous attempt produced no PLAN.md)"
      plan_log="$LOG_DIR/plan-attempt-$(printf '%02d' "$attempt").log"
    fi

    _run_planner "$plan_log"
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

  log "PLAN.md created."
  ralph_dance "Plan ready!"
  cat PLAN.md
fi

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
  iter_sentinel="$LOG_DIR/.iter-start"
  touch "$iter_sentinel"

  iter_log="$LOG_DIR/iter-$(printf '%02d' "$i").log"
  if ((i == 1)); then
    iter_prompt="/skill:code-agent Iteration $i of $MAX_ITER. Read PLAN.md and complete as many [ ] or [~] tasks as you safely can in this iteration. Specifically: find the earliest group (tasks tagged '(group:N)') that still has unfinished tasks, and complete EVERY unfinished task in that group before stopping. Untagged tasks are singleton groups — do them one at a time. Stop the iteration once that group is fully [x], so the next iteration can pick up the following group with fresh context.

HARD REQUIREMENTS — failing any of these means the iteration failed:

(A) You MUST create or modify at least one source file on disk by invoking the Write or Edit tool. Emitting code inside a fenced \`\`\` block in chat does NOT create a file and counts as failure. If you write 'mkdir src' or 'cat > src/main.c' as text, that is NOT execution — you must invoke the Bash or Write tool.

(B) Do not say 'shall I proceed', 'is that okay', or show the user code for approval. Just write it.

(C) Match PLAN.md exactly. If the plan says print \"hello\", do not print \"Hello, World!\".

(D) TESTS: for every implementation task you complete in this group, you MUST also complete its paired unit-test task by writing the test to disk. After finishing the group, run the test command from PLAN.md's '## Test Command' section yourself via the Bash tool. If tests fail, fix the code or tests and re-run until they pass before marking the group [x]. Do NOT mark any task [x] whose tests have not been run and observed to pass. Tasks marked '(no-test)' are exempt from the test requirement but still must be implemented.

(E) The test command MUST run unit tests ONLY — it MUST NOT invoke the main program / produced binary as an end-to-end smoke check. If PLAN.md's '## Test Command' currently runs the application binary (e.g. './my_program', 'node app.js', 'python main.py'), REPLACE it with a real unit-test command ('make check', 'ctest', 'pytest tests/', etc.) and write the missing unit tests. Building the binary is fine; running it is not. All filesystem paths in Makefiles, scripts and tests MUST be project-relative — never write to absolute paths like '/my_program'.

Rules: (1) write all code directly to disk without asking for confirmation; (2) only modify files inside $PROJECT_DIR; (3) external libraries/modules listed in PLAN.md may be installed and used; do not pull in dependencies that PLAN.md does not mention; (4) update PLAN.md to mark each task [x] as you finish it."
    turbo-pi-run \
      --session-dir "$SESSION_DIR" \
      --append-system-prompt "$AUTONOMOUS_SYSTEM" \
      -p "$iter_prompt" \
      2>&1 | tee "$iter_log"
  else
    iter_prompt="Iteration $i of $MAX_ITER. Re-read PLAN.md, find the earliest group with unfinished [ ] or [~] tasks, and complete every task in that group under the same hard requirements (write to disk via tools, match PLAN.md exactly, write+run paired tests, mark tasks [x] as you finish). Stop when that group is fully [x]."
    turbo-pi-run \
      --session-dir "$SESSION_DIR" \
      --continue \
      --append-system-prompt "$AUTONOMOUS_SYSTEM" \
      -p "$iter_prompt" \
      2>&1 | tee "$iter_log"
  fi

  # Detect whether the agent actually wrote any code to disk.
  # Exclude PLAN.md (bookkeeping) and the .ralph/ log directory itself.
  code_written=$(find . \
    -not -path './.ralph/*' \
    -not -name 'PLAN.md' \
    -newer "$iter_sentinel" \
    -type f 2>/dev/null | head -1)

  # Fallback: the agent sometimes emits code as fenced ```<lang> blocks with a
  # '// path/to/file' header instead of invoking Write. Salvage those blocks
  # before declaring the iteration stalled.
  if [[ -z "$code_written" ]]; then
    extractor="$(dirname "$(readlink -f "$0")")/turbo-ralph-extract.py"
    if [[ -x "$extractor" ]]; then
      log "No files written — attempting fenced-block salvage from $iter_log"
      "$extractor" "$iter_log" --root "$PROJECT_DIR" 2>&1 | tee -a "$iter_log" || true
      code_written=$(find . \
        -not -path './.ralph/*' \
        -not -name 'PLAN.md' \
        -newer "$iter_sentinel" \
        -type f 2>/dev/null | head -1)
      [[ -n "$code_written" ]] && log "Salvage recovered code from fenced blocks."
    fi
  fi

  if [[ -z "$code_written" ]]; then
    ralph_sad "Ralph tried really hard but wrote no code. Giving up."
    log "Iteration $i produced no code files — stalled."
    exit 3
  fi

  ralph_dance "Iteration $i done"
done

# ── Final test gate ──────────────────────────────────────────────────────────
# The code-agent runs tests itself before marking tasks [x], so we only verify
# once at the end of the run. If the suite fails, re-invoke the agent up to
# MAX_TEST_RETRIES times to repair, resuming the same session so it sees its
# prior work.
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
      --session-dir "$SESSION_DIR" \
      --continue \
      --append-system-prompt "$AUTONOMOUS_SYSTEM" \
      -p "The test command for this project (\`$cmd\`) is failing at the end of the run. Last test output (tail):

$test_output

Diagnose the failure, fix the code or the tests so the test command exits zero, and write the fixes to disk. Do NOT mark new PLAN.md tasks [x] — only fix what is needed to make tests pass. Do not ask for confirmation; write directly to disk." \
      2>&1 | tee "$retry_log"
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
