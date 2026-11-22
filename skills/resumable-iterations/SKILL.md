---
name: resumable-iterations
description: Work in small, resumable iterations with actionable plans and explicit checkpoints. Use for coding, debugging, refactoring, and other multi-step tasks that may be interrupted or resumed later.
---

# Resumable iterations

Treat every task as a sequence of small, independently useful iterations. Optimize
for reliable progress on a small model: keep the current context focused, avoid
large speculative plans, and leave the worktree understandable after every step.

## Plan before changing

Before making changes, write or update a task plan in `PLAN.md` at the repository
root. Use a short checklist of concrete, verifiable actions:

```markdown
# Plan

- [ ] Inspect the relevant code and existing tests.
- [ ] Implement the smallest change that addresses the requirement.
- [ ] Run the focused validation command.
- [ ] Review the diff and record any remaining work.
```

Each item should describe one outcome, not a vague phase. Add dependencies or
important decisions directly to the item. Do not create a plan for a trivial
one-file change unless the task has meaningful interruption risk.

## Work in iterations

For each iteration:

1. Select the smallest unchecked plan item.
2. Inspect only the files and context needed for that item.
3. Make one coherent, minimal change.
4. Run the narrowest relevant test, build, or check.
5. Update `PLAN.md`: mark the item complete, record the validation result, and
   add newly discovered follow-up items.

Prefer changes that leave the project buildable and testable. Do not combine
unrelated cleanup with the current iteration.

## Leave resumable checkpoints

Before stopping, ensure the plan reflects reality. Record:

- what changed;
- which checks passed or failed;
- the exact next actionable item;
- blockers, assumptions, or decisions a future iteration must know.

If work is interrupted, the next iteration must be able to resume from
`PLAN.md` and the current diff without relying on conversation history.

## Keep context small

Use focused searches and targeted file reads. Summarize findings in the plan
instead of repeatedly rereading large files. Prefer existing helpers and tests,
and ask for clarification when a design choice cannot be resolved safely from
the repository.
