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

## Starting a Session

At the start of every session, read or create `PLAN.md` in the project root:

```bash
cat PLAN.md 2>/dev/null || echo "No PLAN.md yet"
```

If no plan exists, draft one from the task description before writing any code.

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

Each increment:
1. Read `PLAN.md`, find first `[ ]` task, mark `[~]`
2. Write the implementation (smallest working unit)
3. Write a test for it (see Testing below)
4. Compile and run — fix until green
5. Mark task `[x]` in `PLAN.md`, add a note if anything was surprising
6. Commit

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
2. Write a one-line summary under `## Notes` in `PLAN.md`
3. Archive: `mv PLAN.md PLAN-done-$(date +%Y%m%d).md`
