local M = {}

local command = {
  "pi",
  "--theme",
  vim.fn.stdpath("config") .. "/themes/pi-retrobox.json",
  "--use-theme",
  "retrobox",
}

local function opts()
  return {
    cwd = LazyVim.root(),
    count = 1,
    win = {
      position = "right",
      width = 0.5,
      wo = { number = false, relativenumber = false, signcolumn = "no" },
    },
  }
end

-- resume: a stopped task's leftover terminal starts (resumes) pi instead of hiding.
function M.toggle(resume)
  local core = require("util.pi_issues")
  local workspace = core.current()
  if workspace then
    local job = core.jobs[workspace.id]
    if job then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_buf(win) == job.buf then
          if resume and job.exited then
            return core.task(function()
              core.start(workspace)
              if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == job.buf then
                vim.api.nvim_win_close(win, false)
              end
            end)
          end
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
  if vim.fn.executable("pi") ~= 1 then return vim.notify("pi is not installed", vim.log.levels.WARN) end
  Snacks.terminal.toggle(command, opts())
end

local function running()
  local options = opts()
  options.create = false
  local term = Snacks.terminal.get(command, options)
  if term and term:buf_valid() and vim.bo[term.buf].buftype == "terminal" then return term end
end

function M.send(visual)
  local core = require("util.pi_issues")
  local workspace = core.current()
  local source = vim.api.nvim_get_current_buf()
  local first, last_line
  if visual then
    if vim.fn.mode():sub(1, 1) == "\22" then
      return vim.notify("Use a character or line selection, not a rectangular selection", vim.log.levels.WARN)
    end
    vim.cmd("normal! \27")
    first, last_line = vim.fn.line("'<"), vim.fn.line("'>")
  end
  local term = not workspace and running() or nil
  local job = workspace and core.jobs[workspace.id]
  if not term and (not job or job.exited) then return vim.notify("Start pi with Space a p", vim.log.levels.WARN) end
  local file = vim.api.nvim_buf_get_name(source)
  if file == "" then return vim.notify("Save the buffer first", vim.log.levels.WARN) end
  local root = workspace and workspace.path or opts().cwd
  if not core.inside(file, root) then
    return vim.notify(
      "This file is outside the current pi worktree; switch issue tabs before sending",
      vim.log.levels.WARN
    )
  end
  local path = core.real(file):sub(#core.real(root) + 2)
  local lines
  if visual then
    lines = vim.api.nvim_buf_get_lines(source, first - 1, last_line, false)
  else
    lines = vim.api.nvim_buf_get_lines(source, 0, -1, false)
  end
  local content = table.concat(lines, "\n")
  if #content > 100000 then
    return vim.notify("Context is larger than 100 KB; send a smaller selection", vim.log.levels.WARN)
  end
  local label = visual and (" lines %d-%d"):format(first, last_line) or ""
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
  local core = require("util.pi_issues")
  local workspace = core.current()
  local job = workspace and core.jobs[workspace.id]
  if not job or job.exited then return vim.notify("Start the task's pi with Space a p first", vim.log.levels.WARN) end
  if not job.model or job.model == "" or job.model == "unavailable" then
    return vim.notify("Pi has not reported its active model yet; inspect its terminal", vim.log.levels.WARN)
  end
  local text = "Use the existing subagent tool with agent: reviewer, async: false, model: "
    .. job.model
    .. " and the current cwd. Review this task's changes against its description and repository instructions. "
    .. "Do not edit files, use workflow scripts, or start background agents."
  vim.api.nvim_chan_send(job.channel, "\27[200~" .. text .. "\27[201~")
  core.show(workspace)
end

return M
