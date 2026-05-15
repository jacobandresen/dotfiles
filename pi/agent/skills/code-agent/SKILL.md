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
- `clang-tidy` is on PATH (installed by `scripts/turbo-setup.sh`)
- A `.clang-tidy` config file exists at the project root (see Linting below)

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
5. Run clang-tidy — fix all warnings before continuing (see Linting below)
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

## Linting

Run clang-tidy after every successful compilation. All warnings are errors — do not proceed until the output is clean.

```bash
# With a compilation database (CMake — preferred)
clang-tidy -p build src/*.c
clang-tidy -p build src/*.cpp

# Without a compilation database (fallback)
clang-tidy src/*.c -- -std=c11 -Wall
clang-tidy src/*.cpp -- -std=c++17 -Wall
```

If the project has no `.clang-tidy` file, create one at the root before the first lint run:

```yaml
Checks: >
  clang-analyzer-*,
  cppcoreguidelines-*,
  modernize-*,
  performance-*,
  readability-*,
  bugprone-*
WarningsAsErrors: "*"
HeaderFilterRegex: "src/.*"
```

Common clang-tidy warnings and fixes:

| Warning | Fix |
|---|---|
| `cppcoreguidelines-pro-bounds-*` | Replace raw array indexing with bounds-checked access or `at()` |
| `bugprone-use-after-move` | Don't use a value after `std::move` |
| `modernize-use-nullptr` | Replace `NULL` / `0` with `nullptr` |
| `readability-magic-numbers` | Extract literals into named constants |
| `performance-unnecessary-copy-initialization` | Use `const&` or `std::move` |
| `clang-analyzer-unix.Malloc` | Ensure every `malloc` has a matching `free` |

Never suppress a warning with `// NOLINT` unless a comment explains an external constraint that makes the fix impossible.

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

## Error Handling

- Compilation errors: read the full error, fix the root cause, recompile
- Linker errors: check `-lSDL2` is present; check header paths with `-I`
- SDL init failures: always check return values — `SDL_Init` returns non-zero on failure
- Never ignore compiler warnings by casting to `void` or `(void)` to silence them — fix them

## File Layout

```
project/
  PLAN.md
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
2. Run clang-tidy across all source files — output must be clean
3. Write a one-line summary under `## Notes` in `PLAN.md`
4. Archive: `mv PLAN.md PLAN-done-$(date +%Y%m%d).md`
