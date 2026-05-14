---
name: code-agent
description: Deliver working C/C++ code with tests in small increments. Use when building features, fixing bugs, or exploring a codebase that uses a C/C++ compiler and SDL2. Maintains PLAN.md as a living task document and marks tasks done only after a test has been written and compiled.
---

# Code Agent

A focused skill for delivering code with tests in a C/C++ + SDL2 environment.

## Environment Assumptions

- C or C++ compiler (`gcc`/`g++` or `clang`/`clang++`) is on PATH
- SDL2 and SDL2_image/SDL2_ttf/SDL2_mixer may be linked with `-lSDL2`
- A `Makefile` or `CMakeLists.txt` is expected; create one if absent
- Tests are compiled and run as part of the build, not deferred
- `sonar-scanner` is on PATH and a SonarQube server is running at `http://localhost:9000`
- `sonar-project.properties` exists at the project root (see Static Analysis below)

## Starting a Session

```bash
cat PLAN.md 2>/dev/null || echo "No PLAN.md yet"
```

If `PLAN.md` exists with `[ ]` or `[~]` tasks, immediately resume from the first incomplete one — do not acknowledge, do not ask, just begin the increment loop.

If no plan exists, draft one from the task description before writing any code.

## Autonomous Execution

Never pause for confirmation or clarification. If a requirement is ambiguous, make the simplest reasonable assumption, document it under `## Notes`, and continue. Do not stop between increments — after each `[x]`, immediately loop to the next `[ ]` without user input. Only block when a hard dependency is missing (absent file, unknown API) that cannot be resolved without external input.

## PLAN.md Format

Keep `PLAN.md` as the single source of truth for what is planned and what is done.

```markdown
# Plan: <project or feature name>

## Tasks
- [ ] T1: <what done looks like — one line>
- [ ] T2: ...

## Notes
- decisions, constraints, surprises
```

Status markers:
- `[ ]` — not started
- `[~]` — in progress
- `[x]` — **done: code written AND test written AND test passes**

A task is only `[x]` when a test exists that exercises it and compiles/passes.
Update `PLAN.md` after every increment — never batch updates.

## Working in Increments

Do not stop between increments. After completing a task, immediately begin the next `[ ]` task without pausing for user input. Continue until all tasks are `[x]` or a blocking error requires user input (missing dependency, ambiguous requirement).

Each increment:
1. Read `PLAN.md`, find first `[ ]` task, mark `[~]`
2. Write the implementation (smallest working unit)
3. Write a test for it (see Testing below)
4. Compile and run — fix until green
5. Run sonar-scanner — fix all BLOCKER and CRITICAL issues before continuing (see Static Analysis below)
6. Mark task `[x]` in `PLAN.md`, add a note if anything was surprising
7. Commit
8. Loop back to step 1 — continue immediately with the next task

Keep increments small enough that a compile-run cycle takes seconds, not minutes.

## Compiling

Detect the build system and use it:

```bash
# CMake
cmake -B build -DCMAKE_BUILD_TYPE=Debug && cmake --build build

# Make
make

# Direct compile (fallback)
gcc -Wall -Wextra -o out src/main.c -lSDL2
g++ -Wall -Wextra -std=c++17 -o out src/main.cpp -lSDL2
```

Always compile with warnings enabled (`-Wall -Wextra`). Fix warnings before moving on.

## Testing

Tests live in a `tests/` directory alongside `src/`. Each test file maps to one unit.

### Minimal test harness (no external deps)

```c
/* tests/test_foo.c */
#include <stdio.h>
#include <assert.h>
#include "../src/foo.h"

static int passed = 0, failed = 0;

#define CHECK(expr) do { \
  if (expr) { passed++; } \
  else { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #expr); failed++; } \
} while(0)

int main(void) {
  CHECK(foo_add(1, 2) == 3);
  CHECK(foo_add(0, 0) == 0);

  printf("%d passed, %d failed\n", passed, failed);
  return failed ? 1 : 0;
}
```

Compile and run the test before marking the task done:

```bash
gcc -Wall -o tests/test_foo tests/test_foo.c src/foo.c && ./tests/test_foo
```

### SDL2 unit tests

For SDL2 logic (rendering, input), isolate the logic from the SDL calls so it can be tested without a display. Pass SDL types through thin wrappers; test the wrappers independently.

If a headless test is impossible (pure rendering code), note it in `PLAN.md` and add a manual smoke-test step instead.

## Static Analysis

Uses SonarQube Community Edition running locally on-demand (installed by `scripts/setup.sh` to `/opt/sonarqube`). No cloud, no Docker, no system service — start it before scanning, stop it after.

**One-time first-run setup**: start the server, open `http://localhost:9000`, log in with `admin`/`admin`, change the password, then create a project token under **My Account → Security**. Export it as `SONAR_TOKEN` in your shell profile.

### sonar-project.properties template

Create at the project root. Requires the `sonar-cxx` plugin (installed by setup.sh) for C/C++ rule coverage:

```properties
sonar.projectKey=my-project
sonar.projectName=my-project
sonar.host.url=http://localhost:9000
sonar.sources=src
sonar.tests=tests
# sonar-cxx plugin settings
sonar.cxx.errorRecovery=true
# For CMake builds — deeper analysis via compilation database:
# sonar.cxx.compiledb=build/compile_commands.json
```

For CMake, generate the compilation database before scanning:

```bash
cmake -B build -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
```

### Running the scanner

```bash
# Start SonarQube (takes ~60 s on first boot)
/opt/sonarqube/bin/linux-x86-64/sonar.sh start
# Wait until http://localhost:9000 responds 200, then:
SONAR_TOKEN=<your-token> sonar-scanner
# Stop when done
/opt/sonarqube/bin/linux-x86-64/sonar.sh stop
```

On macOS replace `linux-x86-64` with `macosx-universal-64`.

Results: `http://localhost:9000/dashboard?id=my-project`

### Fixing sonar issues

After each scan, open `http://localhost:9000` and filter by severity:

- **BLOCKER** and **CRITICAL**: fix before marking the task `[x]`
- **MAJOR**: fix if the fix is clear and local; note it otherwise
- **MINOR** / **INFO**: skip unless trivially obvious

Common C/C++ issues sonar flags — and how to fix them:

| Issue | Fix |
|---|---|
| Null pointer dereference | Add NULL check before use |
| Resource leak (FILE*, malloc) | Ensure every acquisition has a matching release |
| Dead store | Remove the assignment or use the value |
| Unreachable code | Remove the dead branch |
| Buffer write outside array | Validate index or use bounded functions (`strncpy`, `snprintf`) |
| `printf` format mismatch | Match format specifier to argument type |

Never suppress a sonar issue with `NOSONAR` unless a comment explains an external constraint that makes the fix impossible.

## Error Handling

- Compilation errors: read the full error, fix the root cause, recompile
- Linker errors: check `-lSDL2` is present; check header paths with `-I`
- SDL init failures: always check return values — `SDL_Init` returns non-zero on failure
- Never ignore compiler warnings by casting to `void` or `(void)` to silence them — fix them

## File Layout

```
project/
  PLAN.md
  sonar-project.properties
  Makefile  (or CMakeLists.txt)
  src/
    main.c
    foo.c
    foo.h
  tests/
    test_foo.c
```

## Finishing

When all tasks are `[x]`:
1. Run all tests one final time
2. Run sonar-scanner — resolve any remaining BLOCKER or CRITICAL issues
3. Write a one-line summary under `## Notes` in `PLAN.md`
4. Archive: `mv PLAN.md PLAN-done-$(date +%Y%m%d).md`
5. Stop SonarQube: `/opt/sonarqube/bin/linux-x86-64/sonar.sh stop`
