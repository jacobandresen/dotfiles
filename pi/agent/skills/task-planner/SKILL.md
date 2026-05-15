---
name: task-planner
description: Break down complex, multi-step goals into a tracked plan and work through them reliably across long sessions. Use when a task has 3+ steps, will take a long time, or needs to be resumable if the session is interrupted. Handles checkpoint files so work isn't lost.
---

# Task Planner

Use this skill at the start of any task that is complex, multi-step, or likely to run long.

## Starting a Task

First check if `PLAN.md` already exists with `[ ]` or `[~]` tasks. If it does, skip planning and immediately resume from the first incomplete step — do not acknowledge, do not ask, just begin.

If no plan exists, create `PLAN.md` in the project root:

```markdown
# Plan: <goal in one line>

## Steps
- [ ] Step 1: describe what done looks like
- [ ] Step 2: ...
- [ ] Step 3: ...

## Notes
- key constraints or decisions made so far
```

Each step must be actionable: a concrete action with a clear done condition, not a topic or goal. Bad: "Handle errors." Good: "Wrap `open_file` call in try/except, log the error, return None." If a step can't be executed without further planning, break it down before starting it.

## Autonomous Execution

Never pause for confirmation or clarification. If a requirement is ambiguous, make the simplest reasonable assumption, document it under `## Notes`, and continue. Do not stop between steps.

After each step completes, immediately begin the next `[ ]` step without user input. Continue until all steps are `[x]` or a hard blocker (missing dependency, unresolvable ambiguity) requires input. Only block on true hard stops — everything else is solvable; solve it and keep going.

## Working Through Steps

Before starting each step:
1. Read `PLAN.md` to confirm current position
2. Mark the step `[~]` (in progress) as you begin
3. Complete the step, mark `[x]`, add a one-line note under `## Notes` if anything was surprising
4. Loop back to step 1 — continue immediately with the next `[ ]` step

## Resuming an Interrupted Session

At the start of a resumed session:

```bash
cat PLAN.md
```

Pick up from the first `[ ]` or `[~]` step. Re-read any relevant notes before continuing.

## Handoff to Code Agent

When the plan involves implementation work, write `PLAN.md` to the **project root** (the directory containing `src/`, `Makefile`, or `CMakeLists.txt`). The `code-agent` skill picks it up by running `cat PLAN.md` from that same directory.

The code-agent only understands **C and C++**. When writing steps that involve code:
- Specify C or C++ explicitly if relevant
- Do not plan steps that require other languages (Python, Rust, Go, etc.) — if the task needs them, note it as a hard blocker
- Frame implementation steps in terms of files (`src/foo.c`, `src/foo.h`) and build tools (`gcc`, `g++`, `cmake`, `make`)

## Finishing

When all steps are `[x]`:
1. Summarize what was accomplished
2. Archive: `mv PLAN.md PLAN-done-$(date +%Y%m%d).md`

## When Plans Change

Update `PLAN.md` immediately when scope changes — don't work from a stale plan. Add new steps, cross out abandoned ones with strikethrough, and note why.

## Keeping Tasks Small Enough to Track

If a step takes more than ~10 tool calls to complete, break it into sub-steps. Steps should be completable in a single turn or a small cluster of turns.
