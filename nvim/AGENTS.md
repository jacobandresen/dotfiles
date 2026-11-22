This is a Neovim configuration built on LazyVim.

Only edit files inside this directory. Do not touch files inside plugin library paths.

External tools this config expects: [DEPENDENCIES.md](DEPENDENCIES.md).

## AI

Only pi-agent is available in a terminal split. New sessions use pi-agent's
configured default model, with the pinned pi-subagents extension for foreground
delegation using the active session model. Keep the AI menu and keymaps limited to pi.
Task workflows default to local `.tasks/*.md` files. GitHub operations require
`vim.g.pi_issues.github_enabled = true`; keep local task paths offline.
