---
name: git-workflow
description: Git operations for daily coding work — staging, committing with clear messages, branch management, reviewing diffs, and creating PRs with the gh CLI. Use when the user wants to commit changes, review what changed, manage branches, or open a pull request.
---

# Git Workflow

## Before Committing

Always inspect before staging:

```bash
git status
git diff                    # unstaged changes
git diff --cached           # staged changes
git diff --stat HEAD        # summary of all changes
```

Stage specific files (never `git add .` blindly — may grab .env or binaries):

```bash
git add path/to/file
git add -p                  # interactive hunk staging
```

## Commit Messages

- Imperative mood, ≤72 chars on first line, no trailing period
- Blank line before body if body is needed
- WHY matters more than WHAT — the diff shows what changed

```
fix lua plugin order breaking telescope keymaps

Lazy loads telescope before which-key, causing keymap registration
to fail on first open. Swap load order in plugins/ui.lua.
```

## Checking History

```bash
git log --oneline -20
git log --oneline --graph --all -15
git show HEAD
git log -p -1              # full diff of last commit
```

## Branching

```bash
git switch -c feature/name
git switch main
git merge --no-ff feature/name
git branch -d feature/name  # after merge
```

## Pull Requests (gh CLI)

```bash
gh pr create --title "short title" --body "$(cat <<'EOF'
## Summary
- what changed and why

## Test plan
- [ ] tested locally
EOF
)"
gh pr view
gh pr diff
gh pr checks
```

## Undoing Things

```bash
git restore path/to/file          # discard unstaged changes to file
git restore --staged path/to/file # unstage without losing changes
git revert HEAD                   # new commit that undoes last commit (safe)
```

Never use `git reset --hard` or `git push --force` without confirming with the user first.
