local M = {}

local command = "pi"

local function opts()
  return { cwd = LazyVim.root(), win = { position = "right", width = 0.4 } }
end

function M.toggle()
  if vim.fn.executable(command) ~= 1 then
    return vim.notify("pi is not installed", vim.log.levels.WARN)
  end
  Snacks.terminal.toggle(command, opts())
end

local function running()
  local term = Snacks.terminal.get(command, opts(), false)
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
    return vim.notify("Start pi with Space a p", vim.log.levels.WARN)
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

return M
