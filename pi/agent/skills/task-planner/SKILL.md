---
name: task-planner
description: Break down complex, multi-step goals into a tracked plan and work through them reliably across long sessions. Use when a task has 3+ steps, will take a long time, or needs to be resumable if the session is interrupted. Handles checkpoint files so work isn't lost.
---

# Task Planner

Use this skill at the start of any task that is complex, multi-step, or likely to run long.

## Starting a Task

Create `.pi/task.md` in the working directory at the start:

```bash
mkdir -p .pi
```

Write the plan as a checklist with clear, atomic steps:

```markdown
# Task: <goal in one line>

## Steps
- [ ] Step 1: describe what done looks like
- [ ] Step 2: ...
- [ ] Step 3: ...

## Notes
- key constraints or decisions made so far
```

## Working Through Steps

Before starting each step:
1. Read `.pi/task.md` to confirm current position
2. Mark the step `[~]` (in progress) as you begin
3. Mark `[x]` as soon as it's verifiably complete

After completing a step, write a one-line note under `## Notes` describing any decision or surprise.

## Resuming an Interrupted Session

At the start of a resumed session:

```bash
cat .pi/task.md
```

Pick up from the first `[ ]` or `[~]` step. Re-read any relevant notes before continuing.

## Finishing

When all steps are `[x]`:
1. Summarize what was accomplished
2. Archive: `mv .pi/task.md .pi/task-done-$(date +%Y%m%d).md`

## When Plans Change

Update `.pi/task.md` immediately when scope changes — don't work from a stale plan. Add new steps, cross out abandoned ones with strikethrough, and note why.

## Keeping Tasks Small Enough to Track

If a step takes more than ~10 tool calls to complete, break it into sub-steps. Steps should be completable in a single turn or a small cluster of turns.
