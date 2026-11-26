-- Unit tests for taskbay.terminal with taskbay.core and Snacks stubbed out.
-- Run: timeout 60 nvim --headless -u NONE -i NONE -l tests/terminal.lua
local plugin = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(plugin)
vim.g.mapleader = " "
local root, bin = vim.fn.tempname(), vim.fn.tempname()
vim.fn.mkdir(root, "p")
vim.fn.mkdir(bin, "p")
_G.LazyVim = { root = function() return root end }
local notes, calls, sent = {}, {}, {}
vim.notify = function(message) notes[#notes + 1] = message end
vim.api.nvim_chan_send = function(channel, text) sent[#sent + 1] = { channel = channel, text = text } end
local core = { jobs = {}, live_count = 0 }
function core.current() return core.workspace end
function core.live() return core.live_count end
function core.task(fn) fn() end
function core.start() calls[#calls + 1] = "start" end
function core.show() calls[#calls + 1] = "show" end
function core.real(path) return path end
function core.inside(path, dir) return vim.startswith(path, dir .. "/") end
function core.settings() return { pi = {} } end
function core.root() return root end
function core.key() return "Space a p" end
function core.agent() return require("taskbay.agents.pi") end
package.loaded["taskbay.core"] = core
local agents = require("taskbay.terminal")

local function expect(pattern, fn)
  notes = {}
  fn()
  assert(notes[#notes] and notes[#notes]:find(pattern, 1, true), pattern .. " expected, got " .. vim.inspect(notes))
end
local function reset(workspace, job)
  vim.cmd("silent! only")
  core.workspace, core.jobs, calls, sent = workspace, {}, {}, {}
  if job then core.jobs[workspace.id] = job end
end
local function source(name, lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_win_set_buf(0, buf)
  if name then vim.api.nvim_buf_set_name(buf, root .. "/" .. name) end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines or {})
  return buf
end
local function wins() return #vim.api.nvim_tabpage_list_wins(0) end
local workspace = { id = "w", path = root }
local term_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_call(term_buf, function() vim.fn.jobstart({ "cat" }, { term = true }) end)
local shown = 0
local term = { buf = term_buf, buf_valid = function() return true end }
function term:show() shown = shown + 1; return self end
function term:focus() end

-- toggle without a task: needs pi on PATH and Snacks.
reset(nil)
local path = vim.env.PATH
vim.env.PATH = bin
expect("pi is not installed", agents.toggle)
vim.fn.writefile({ "#!/bin/sh" }, bin .. "/pi")
vim.fn.setfperm(bin .. "/pi", "rwxr-xr-x")
expect("Snacks is not available", agents.toggle)
assert(not agents.available(), "Nothing to send to without pi or Snacks")
local toggled
_G.Snacks = { terminal = {
  toggle = function(cmd, options) toggled = { cmd = cmd, options = options } end,
  get = function(_, options) assert(options.create == false); return term.attached and term or nil end,
} }
agents.toggle()
assert(toggled.cmd[1] == "pi" and toggled.options.cwd == root, "Plain pi toggles a Snacks terminal in the root")
vim.env.PATH = path

-- toggle inside a task tab.
reset(workspace)
agents.toggle()
assert(calls[1] == "start", "A task without a job starts pi")
reset(workspace, { buf = term_buf })
agents.toggle()
assert(calls[1] == "show", "A live hidden job is shown")
reset(workspace, { buf = term_buf, exited = true })
agents.toggle()
assert(calls[1] == "start", "An exited hidden job restarts")
reset(workspace, { buf = term_buf })
vim.cmd("vsplit")
vim.api.nvim_win_set_buf(0, term_buf)
agents.toggle()
assert(wins() == 1 and #calls == 0, "A shown job's split closes")
vim.api.nvim_win_set_buf(0, term_buf)
agents.toggle()
assert(wins() == 1 and vim.api.nvim_get_current_buf() ~= term_buf, "The last window swaps to an empty buffer")
reset(workspace, { buf = term_buf, exited = true })
vim.cmd("vsplit")
vim.api.nvim_win_set_buf(0, term_buf)
agents.toggle(true)
assert(calls[1] == "start" and wins() == 2, "Resume restarts pi and leaves the leftover window for the new terminal")
vim.cmd("only")
reset(workspace, { buf = term_buf, exited = true })
vim.api.nvim_win_set_buf(0, term_buf)
agents.toggle()
assert(#calls == 0 and vim.api.nvim_get_current_buf() ~= term_buf, "Without resume an exited terminal just hides")

-- send: refusals.
reset(nil)
source("plain.txt", { "x" })
expect("Start the agent with Space a p", function() agents.send(false) end)
reset(workspace, { channel = 7, exited = true })
expect("Start the agent with Space a p", function() agents.send(false) end)
reset(workspace, { channel = 7 })
source(nil, { "x" })
expect("Save the buffer first", function() agents.send(false) end)
vim.api.nvim_buf_set_name(0, vim.fn.tempname())
expect("outside the current task's worktree", function() agents.send(false) end)
source("big.txt", { ("x"):rep(100001) })
expect("larger than 100 KB", function() agents.send(false) end)
assert(#sent == 0, "Refusals send nothing")

-- send: whole file (never reads stale visual marks), selections and plain terminals.
vim.keymap.set("x", "<F2>", function() agents.send(true) end)
local function select(keys)
  sent = {}
  vim.api.nvim_feedkeys(vim.keycode(keys .. "<F2>"), "x", false)
  vim.cmd("stopinsert")
  return sent[1] and sent[1].text
end
source("a.py", { "café ok", "line two" })
vim.bo.filetype = "python"
vim.cmd("normal! gg0vj$\27")
vim.api.nvim_buf_set_lines(0, 1, -1, false, {})
agents.send(false)
vim.cmd("stopinsert")
assert(sent[1].channel == 7 and calls[1] == "show", "Whole files reach the task's pi")
assert(sent[1].text == '\27[200~File: "a.py" (unsaved buffer snapshot)\n```python\ncafé ok\n```\n\27[201~', sent[1].text)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "café ok", "line two" })
assert(select("gg0v3l"):find('File: "a.py" 1:1-1:4 (unsaved buffer snapshot)\n```python\ncafé\n', 1, true),
  "Charwise selections keep a multibyte last character whole")
assert(select("ggVj"):find(" lines 1-2 (unsaved buffer snapshot)\n```python\ncafé ok\nline two\n", 1, true))
expect("rectangular selection", function() assert(select("gg0<C-v>j") == nil) end)
vim.cmd("normal! \27")
reset(nil)
term.attached = true
assert(agents.available(), "A plain pi terminal accepts context")
source("other.txt", { "x" })
agents.send(false)
vim.cmd("stopinsert")
assert(sent[1].channel == vim.bo[term_buf].channel and shown == 1, "Without a task, context goes to the pi terminal")
core.live_count, term.attached = 1, false
assert(agents.available(), "A live managed agent accepts context")

-- review.
reset(workspace, { channel = 7, exited = true })
expect("Start the task's agent", agents.review)
reset(workspace, { channel = 7 })
expect("active model", agents.review)
core.jobs.w.model = "ollama/m"
agents.review()
assert(sent[1].channel == 7 and sent[1].text:find("model: ollama/m and", 1, true) and calls[1] == "show")

vim.fn.delete(root, "rf")
vim.fn.delete(bin, "rf")
print("taskbay terminal: toggle, send and review paths covered")
vim.cmd("qa!")
