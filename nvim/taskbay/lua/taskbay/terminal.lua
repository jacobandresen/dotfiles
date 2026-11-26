-- The agent terminal outside the task panel: show / hide a task's agent, a standalone
-- agent elsewhere, and sending files, selections and review requests to it.
local M = {}

local function command() return require("taskbay.core").agent().terminal() end

local function opts()
  return {
    cwd = require("taskbay.core").root(),
    count = 1,
    win = {
      position = "right",
      width = 0.5,
      wo = { number = false, relativenumber = false, signcolumn = "no" },
    },
  }
end

-- resume: a stopped task's leftover terminal starts (resumes) the agent in its place instead of hiding.
function M.toggle(resume)
  local core = require("taskbay.core")
  local workspace = core.current()
  if workspace then
    local job = core.jobs[workspace.id]
    if job then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_buf(win) == job.buf then
          if resume and job.exited then return core.task(function() core.start(workspace) end) end
          if #vim.api.nvim_tabpage_list_wins(0) == 1 then
            vim.api.nvim_win_set_buf(win, vim.api.nvim_create_buf(true, false))
          else
            vim.api.nvim_win_close(win, false)
          end
          return
        end
      end
      if not job.exited then return core.show(workspace) end
    end
    return core.task(function() core.start(workspace) end)
  end
  local argv = command()
  if vim.fn.executable(argv[1]) ~= 1 then return vim.notify(argv[1] .. " is not installed", vim.log.levels.WARN) end
  if not Snacks then
    return vim.notify("Snacks is not available yet; try again shortly", vim.log.levels.WARN)
  end
  Snacks.terminal.toggle(argv, opts())
end

local function running()
  if not Snacks then return end
  local options = opts()
  options.create = false
  local term = Snacks.terminal.get(command(), options)
  if term and term:buf_valid() and vim.bo[term.buf].buftype == "terminal" then return term end
end

-- True while context can be sent: a managed agent runs or an agent terminal exists.
function M.available()
  return require("taskbay.core").live() > 0 or running() ~= nil
end

-- The exact text to transfer: whole file, whole selected lines, or the precise
-- character-wise range (a selection may cover part of one line).
local function transfer_text(source)
  local first, last_line = vim.fn.line("'<"), vim.fn.line("'>")
  local mode = vim.fn.visualmode()
  -- getregion keeps a multibyte last character whole; '> marks only its first byte.
  local text = table.concat(vim.fn.getregion(vim.fn.getpos("'<"), vim.fn.getpos("'>"), { type = mode }), "\n")
  return text, mode == "V" and (" lines %d-%d"):format(first, last_line)
    or (" %d:%d-%d:%d"):format(first, vim.fn.col("'<"), last_line, vim.fn.col("'>"))
end

function M.send(visual)
  local core = require("taskbay.core")
  local workspace = core.current()
  local source = vim.api.nvim_get_current_buf()
  if visual then
    if vim.fn.mode():sub(1, 1) == "\22" then
      return vim.notify("Use a character or line selection, not a rectangular selection", vim.log.levels.WARN)
    end
    vim.cmd("normal! \27")
  end
  local term = not workspace and running() or nil
  local job = workspace and core.jobs[workspace.id]
  if not term and (not job or job.exited) then return vim.notify("Start the agent with " .. core.key("agent"), vim.log.levels.WARN) end
  local file = vim.api.nvim_buf_get_name(source)
  if file == "" then return vim.notify("Save the buffer first", vim.log.levels.WARN) end
  local root = workspace and workspace.path or opts().cwd
  if not core.inside(file, root) then
    return vim.notify(
      "This file is outside the current task's worktree; switch task tabs before sending",
      vim.log.levels.WARN
    )
  end
  local path = core.real(file):sub(#core.real(root) + 2)
  -- Only selections read the visual marks: for whole-file sends they may be stale or unset.
  local content, label = table.concat(vim.api.nvim_buf_get_lines(source, 0, -1, false), "\n"), ""
  if visual then content, label = transfer_text(source) end
  if #content > 100000 then
    return vim.notify("Context is larger than 100 KB; send a smaller selection", vim.log.levels.WARN)
  end
  local text = ("File: %s%s (%sbuffer snapshot)\n```%s\n%s\n```\n"):format(
    vim.json.encode(path),
    label,
    vim.bo[source].modified and "unsaved " or "",
    vim.bo[source].filetype,
    content
  )
  vim.api.nvim_chan_send(job and job.channel or vim.bo[term.buf].channel, "\27[200~" .. text .. "\27[201~")
  if workspace then
    core.show(workspace)
  else
    term:show():focus()
  end
  vim.cmd("startinsert")
end

function M.review()
  local core = require("taskbay.core")
  local workspace = core.current()
  local job = workspace and core.jobs[workspace.id]
  if not job or job.exited then return vim.notify("Start the task's agent with " .. core.key("agent") .. " first", vim.log.levels.WARN) end
  if not job.model or job.model == "" then
    return vim.notify("The agent has not reported its active model yet; inspect its terminal", vim.log.levels.WARN)
  end
  local text = core.agent().review(job.model)
  vim.api.nvim_chan_send(job.channel, "\27[200~" .. text .. "\27[201~")
  core.show(workspace)
end

return M
