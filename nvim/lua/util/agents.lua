-- Coding agents (pi, Claude Code, Codex) run as plain CLIs in a Snacks
-- terminal split; this module toggles them and pastes editor context in.
local M = {}

local commands = { pi = "pi", claude = "claude", codex = "codex" }
local last

local function opts()
  return { cwd = LazyVim.root(), win = { position = "right", width = 0.4 } }
end

function M.toggle(name)
  local cmd = commands[name]
  if vim.fn.executable(cmd) ~= 1 then
    return vim.notify(cmd .. " is not installed", vim.log.levels.WARN)
  end
  last = name
  Snacks.terminal.toggle(cmd, opts())
end

-- The terminal of the agent used last, or nil when none is running.
local function running()
  if not last then return end
  local term = Snacks.terminal.get(commands[last], opts(), false)
  if term and term:buf_valid() and vim.bo[term.buf].buftype == "terminal" then return term end
end

-- Paste (bracketed, so newlines don't submit) `@path`, plus the selected lines
-- when called from Visual mode, into the agent's prompt and focus it.
function M.send(visual)
  local lines, first, last_line
  if visual then
    vim.cmd("normal! \27")
    first, last_line = vim.fn.line("'<"), vim.fn.line("'>")
  end
  local term = running()
  if not term then
    return vim.notify("No agent running: Space a p (pi), c (Claude), x (Codex)", vim.log.levels.WARN)
  end
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then
    return vim.notify("Save the buffer first", vim.log.levels.WARN)
  end
  local text = "@" .. vim.fn.fnamemodify(file, ":.")
  if visual then
    lines = vim.api.nvim_buf_get_lines(0, first - 1, last_line, false)
    text = ("%s:%d-%d\n```%s\n%s\n```\n"):format(text, first, last_line, vim.bo.filetype, table.concat(lines, "\n"))
  else
    text = text .. " "
  end
  vim.api.nvim_chan_send(vim.bo[term.buf].channel, "\27[200~" .. text .. "\27[201~")
  term:show():focus()
  vim.cmd("startinsert")
end

function M.toggle_ghost()
  local ok, suggestion = pcall(require, "copilot.suggestion")
  if not ok then return vim.notify("copilot.lua is not loaded", vim.log.levels.WARN) end
  suggestion.toggle_auto_trigger()
end

return M
