---
name: task-planner
description: Break down a software goal into a tracked PLAN.md with a flat task checklist and test command. Use when a task has 3+ steps, will take a long time, or needs to be resumable if the session is interrupted.
---

# Task Planner

Create `PLAN.md` in the current working directory by **invoking the Write tool** with the full
absolute path. Do not emit the plan as chat text or a fenced code block — that does not create
a file. If your turn ends without a Write tool call targeting `PLAN.md`, you have failed.

## PLAN.md format

```markdown
## Files
- [ ] path/to/file — one-line description of what this file does
- [ ] path/to/test_file — unit tests for the above

## Test Command
<single portable shell command that exits non-zero on failure>

## Dependencies
- <every tool and library required, e.g. gcc, make, python3, libcurl>
```

## Rules for the file list

- Every task line **must** start with `- [ ] `. Numbered lists, plain bullets, and heading-style
  tasks are rejected by downstream tooling.
- List files in dependency order: dependencies before dependents.
- Name files explicitly (`src/foo.c`, `tests/test_foo.c`, `Makefile`).
- Pair every implementation file with a unit-test file. Tests call named functions from modules,
  never `main`.
- If a build system is needed (external libraries, multi-file projects), list `Makefile` first.
- For trivial single-file programs: no Makefile, no modules — one source file only.

## Rules for the Test Command

The test command runs in a plain `bash -c` subprocess with **no shell aliases**. Use explicit
binary names only:

| Wrong | Correct |
|-------|---------|
| `python script.py` | `python3 script.py` |
| `make` (with no Makefile in the file list) | `gcc main.c -o main && ./main` |
| `./binary` (graphical/interactive program) | `make` (compile-only smoke test) |

The test command must exit non-zero on failure. For trivial single-file programs, inline
compilation is required — compile and run in the same command.

## Internet safety

**Never** push code, publish packages, or send data to external services without explicit user
approval. This includes:
- `git push` / `gh pr create`
- `npm publish` / `pip upload` / `cargo publish`
- `curl -X POST` or any write request to an external URL
- Deploying to cloud services (Vercel, AWS, GCP, Fly, etc.)

Always stop and ask before any of these. If in doubt, ask.

## Autonomous execution

Never pause for clarification on implementation details. If a requirement is ambiguous, make the
simplest reasonable assumption and continue. Exception: anything that would publish or push data
externally — always ask first.

## When PLAN.md already exists

If `PLAN.md` is present with `[ ]` or `[~]` tasks, skip planning and resume from the first
incomplete step — do not acknowledge, do not ask, just begin.

## Keeping tasks the right size

One task = one complete file to create or modify. Never list individual lines of code as tasks.
If a step would take more than ~10 tool calls, break it into sub-steps.
