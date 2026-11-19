---
name: work-cadence
description: Coordinate bounded autonomous work across coding-agent sessions. Use when planning work blocks, breaks, handoffs, or shared schedules.
---

# Shared work cadence

Use this cadence for autonomous work unless the user sets a different schedule:

- Limit LLM work to 15 minutes, then take at least a 30-minute break. Local
  builds and tests may continue unattended during a break.
- When processes share work, coordinate through the same handoff file:
  `/tmp/work-cadence.md`. Every process reads and updates this
  file. A new process may join by reading the schedule, claiming an open
  15-minute window with a one-minute gap, and recording its task focus before
  starting. Record schedules in UTC, live command handles and status, and the
  next concrete step. Do not assume a process-specific schedule or create a
  separate handoff.
- Never overlap agents' LLM work windows. Leave at least one full minute idle
  between adjacent windows. If work overruns or a window is missed, stop and
  reschedule; do not use another agent's time.
- Before each break, leave a checkpoint for every live command and write the
  next step. On resuming, inspect the worktree, process state, and handoff
  before continuing.
- Scope each work block to a concrete increment that fits in 15 minutes. If a
  task needs longer, write a bounded plan and checkpoint before the break,
  including the next steps and the checks that will verify them. Continue the
  plan in later work blocks.
- Follow user updates to the schedule, and keep the shared handoff current.
