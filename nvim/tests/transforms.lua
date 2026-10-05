-- Run: NVIM_LOG_FILE=/tmp/nvim-transforms.log nvim --headless -u NONE -i NONE -l nvim/tests/transforms.lua
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
local transform = vim.env.TRANSFORM_TEST_SOURCE and dofile(vim.env.TRANSFORM_TEST_SOURCE) or require("util.transform")
local api = vim.api
local messages = {}
vim.notify = function(message) messages[#messages + 1] = message end
local function buffer(lines)
  local buf = api.nvim_create_buf(true, false)
  api.nvim_set_current_buf(buf)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end
local function content(buf)
  return table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end
local function select(keys)
  vim.cmd("normal! " .. keys .. "\27")
end
local function choice(name)
  for _, item in ipairs(transform.transformations) do
    if item.name == name then return item end
  end
  error("Unknown transform")
end
local callback
vim.ui.select = function(_, _, done) callback = done end
local failures = {}
local function check(condition, message)
  if not condition then failures[#failures + 1] = message end
end

local buf = buffer({ " a b " })
transform.run("URL Encode", false)
check(content(buf) == "%20a%20b%20", "URL encode must preserve surrounding spaces")
transform.run("URL Decode", false)
check(content(buf) == " a b ", "URL conversion must round-trip whitespace")

buf = buffer({ "aéz" })
api.nvim_win_set_cursor(0, { 1, 1 })
select("v")
transform.run("Base64 Encode", true)
check(content(buf) == "aw6k=z", "Character selection must include the full UTF-8 character")

buf = buffer({ "untouched", "<first>", "<second>", "untouched" })
api.nvim_win_set_cursor(0, { 2, 3 })
select("Vj")
transform.run("HTML Escape", true)
check(content(buf) == "untouched\n&lt;first&gt;\n&lt;second&gt;\nuntouched", "Line selection must preserve adjacent lines")

buf = buffer({ "<first>", "<second>" })
select("\22jl")
transform.run("HTML Escape", true)
check(content(buf) == "<first>\n<second>", "Unsupported rectangular selection must not change surrounding text")

local original = buffer({ "<original>" })
transform.pick()
local other = buffer({ "<other>" })
callback(choice("HTML Escape"))
check(content(original) == "&lt;original&gt;" and content(other) == "<other>", "Picker must transform its original buffer")

buf = buffer({ "<before>" })
transform.pick()
api.nvim_buf_set_lines(buf, 0, -1, false, { "<changed>" })
callback(choice("HTML Escape"))
check(content(buf) == "<changed>", "Picker must reject stale content")

buf = buffer({ "<readonly>" })
transform.pick()
vim.bo[buf].modifiable = false
local ok = pcall(callback, choice("HTML Escape"))
check(ok and content(buf) == "<readonly>", "Read-only buffer must explain itself without a raw error")

buf = buffer({ "<closed>" })
transform.pick()
api.nvim_set_current_buf(other)
api.nvim_buf_delete(buf, { force = true })
ok = pcall(callback, choice("HTML Escape"))
check(ok and content(other) == "<other>", "Closed source buffer must not transform another buffer")

if #failures > 0 then
  print(table.concat(failures, "\n"))
  vim.cmd("cquit 1")
else
  print("PASS: real transforms preserve whitespace, UTF-8, selection boundaries and picker buffer context")
  vim.cmd("qa!")
end
