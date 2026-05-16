---
name: task-planner
description: Break down a software goal into a tracked PLAN.md with grouped tasks and paired unit tests. Use when a task has 3+ steps, will take a long time, or needs to be resumable if the session is interrupted.
---

# Task Planner

Create `PLAN.md` in the current working directory by **invoking the Write tool** with the full absolute path. Do not emit the plan as chat text or a fenced code block — that does not create a file. If your turn ends without a Write tool call targeting `PLAN.md`, you have failed.

## PLAN.md format

```markdown
# Plan: <goal in one line>

## Dependencies
- <every tool and library required, e.g. gcc, make, libcurl>

## Test Command
<single shell command that runs the full unit-test suite, e.g. `make check` or `pytest tests/`>

## Implementation

### Group 1
- [ ] Create Makefile with `all`, `check`, and `clean` targets  *(no test)*
- [ ] Create `src/greet.c` and `include/greet.h` with a `greet()` function
- [ ] Unit test for `greet()` in `tests/test_greet.c`

### Group 2
- [ ] Create `src/main.c` that includes `greet.h` and calls `greet()`  *(no test)*

## Notes
- key constraints or decisions
```

Rules for task lines:
- Every task line **must** start with `- [ ] `. Numbered lists (`1.`, `2.`), plain bullets (`-`), and heading-style tasks are rejected by downstream tooling.
- Each step must be a concrete action with a clear done condition, not a topic or goal.  
  Bad: "Handle errors."  
  Good: "Wrap `open_file` in try/except, log the error, return `None`."
- Group tasks under `### Group N` subsections. Tasks in the same group are independent; later groups may depend on earlier ones. Do not tag individual task lines with group numbers.
- Tasks with no testable behavior get `*(no test)*` appended at line end.

## Handoff to code-agent

When the plan involves implementation, write PLAN.md to the **current working directory** — this is the project root whether or not source files exist yet. The code-agent picks it up from that same directory.

When writing implementation steps:
- Name files explicitly (`src/foo.c`, `tests/test_foo.c`, `Makefile`).
- Pair every implementation task with a unit-test task. Tests call named functions from modules, never `main`.
- Put the build-system file (Makefile, CMakeLists.txt, pyproject.toml, etc.) as the first task.
- `## Test Command` must exit non-zero on failure and must not run the main binary as an end-to-end check.

## Autonomous execution

Never pause for confirmation or clarification. If a requirement is ambiguous, make the simplest reasonable assumption, document it under `## Notes`, and continue.

## When PLAN.md already exists

If `PLAN.md` is present with `[ ]` or `[~]` tasks, skip planning and resume from the first incomplete step — do not acknowledge, do not ask, just begin.

## Finishing

When all steps are `[x]`: summarize what was accomplished, then archive with `mv PLAN.md PLAN-done-$(date +%Y%m%d).md`.

## Keeping tasks the right size

One task = one complete file to create or modify, or one discrete feature. Never list individual lines of code as tasks. If a step would take more than ~10 tool calls, break it into sub-steps before starting it.
