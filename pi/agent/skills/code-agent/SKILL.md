---
name: code-agent
description: Deliver working C code with tests in small increments. Use when building features, fixing bugs, or exploring a codebase that uses C and a Makefile. Maintains PLAN.md as a living task document and marks tasks done only after a test has been written and compiled.
---

# Code Agent

Deliver simple, readable C with tests, in small increments.

## Rules

- **C only.** No C++, no classes, no templates.
- **Makefile only.** Hand-written, under 50 lines. No CMake, no autotools.
- **libc first.** No dependencies unless the alternative is hundreds of lines.
- **Readable beats clever.** Meaningful names (`customer_count`, not `n`). One idea per line. Guard clauses over nested `if`. Three indent levels is a smell. Named constants, never bare numbers. Comments explain *why*, not *what*.
- **Few, flat files.** One `.c` per concept. No deep trees.
- **No speculative abstractions.** Generalize on the second real use case.
- When in doubt, delete code.

## Loop

Never pause for confirmation. Ambiguous → simplest assumption, log under `## Notes`, continue. After each `[x]`, start the next `[ ]` immediately.

1. `cat PLAN.md` — if `[ ]`/`[~]` tasks exist, resume the first; else draft a plan.
2. Mark task `[~]`.
3. Write the smallest code that can pass a test. **Write to disk immediately** — partial-on-disk beats complete-in-context.
4. Write the test.
5. `make test` until green.
6. `clang-tidy src/*.c -- -std=c11 -Wall` — all warnings are errors. No `// NOLINT` without an external-constraint comment.
7. Mark `[x]`, note surprises, commit.
8. Loop. Keep cycles in seconds.

When all `[x]`: final `make test` + `clang-tidy`, one-line summary under `## Notes`, then `mv PLAN.md PLAN-done-$(date +%Y%m%d).md`.

## PLAN.md

```markdown
# Plan: <name>

## Tasks
- [ ] T1: <what done looks like>

## Notes
- decisions, constraints, surprises
```

`[ ]` not started · `[~]` in progress · `[x]` code + test written and passing. Update after every increment, never batch.

## Layout

```
project/
  PLAN.md  Makefile  .clang-tidy
  src/   main.c foo.c foo.h
  tests/ test_foo.c
```

## Makefile template

```make
CC      = gcc
CFLAGS  = -Wall -Wextra -std=c11 -g
LDFLAGS =

SRC = $(wildcard src/*.c)
OBJ = $(SRC:.c=.o)
BIN = app
TEST_SRC = $(wildcard tests/test_*.c)
TESTS    = $(TEST_SRC:.c=)

all: $(BIN)
$(BIN): $(OBJ); $(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)
tests/test_%: tests/test_%.c $(filter-out src/main.o,$(OBJ))
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)
test: $(TESTS); @for t in $(TESTS); do ./$$t || exit 1; done
clean:; rm -f $(OBJ) $(BIN) $(TESTS)
.PHONY: all test clean
```

## .clang-tidy (if missing)

C-oriented — do not enable `cppcoreguidelines-*` or `modernize-*`.

```yaml
Checks: > clang-analyzer-*, bugprone-*, readability-*, performance-*
WarningsAsErrors: "*"
HeaderFilterRegex: "src/.*"
```

## Test harness

No frameworks (no CMocka/Unity/Check).

```c
#include <stdio.h>
#include "../src/foo.h"

static int passed = 0, failed = 0;
#define CHECK(e) do { if (e) passed++; \
  else { fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #e); failed++; } } while(0)

int main(void) {
  CHECK(foo_add(1, 2) == 3);
  printf("%d passed, %d failed\n", passed, failed);
  return failed ? 1 : 0;
}
```
