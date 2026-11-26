-- taskbay: task workspaces for coding agents. Write tasks as Markdown in .tasks/, run each
-- in its own Git worktree with its own agent, review the diff and merge it back; optionally
-- import and publish issues from a tracker. See the README for options and keys.
local M = {}

-- opts become vim.g.taskbay (later changes to vim.g.taskbay apply at once), then the keys,
-- commands and autocommands are set up.
function M.setup(opts)
  vim.g.taskbay = vim.tbl_extend("force", vim.g.taskbay or {}, opts or {})
  require("taskbay.ui").setup()
end

-- For a statusline: the current task tab's agent, task and status.
function M.statusline() return require("taskbay.ui").statusline() end

-- The changed-files picker of the current task (or of the current repository).
function M.review() return require("taskbay.review").review(require("taskbay.core").current()) end

return M
