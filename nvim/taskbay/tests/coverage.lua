-- Line coverage of the taskbay modules across its test suite, child editors included.
-- Run: nvim --headless -u NONE -i NONE -l tests/coverage.lua
-- LuaJIT's line hook can miss a function's first line (e.g. `return function()`); such
-- misses are listed but do not mean the line never ran.
local self_path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local out = vim.env.TASKBAY_COVERAGE_OUT

-- Tracer: record "module:line" for the taskbay modules and append them on exit.
local function trace()
  jit.off()
  local hits = {}
  debug.sethook(function(_, line)
    local name = debug.getinfo(2, "S").source:match("lua/taskbay/([%w_/]+)%.lua$")
    if name then hits[name .. ":" .. line] = true end
  end, "l")
  vim.api.nvim_create_autocmd("VimLeave", { callback = function()
    local file = assert(io.open(out, "a"))
    for key in pairs(hits) do file:write(key, "\n") end
    file:close()
  end })
end

if vim.env.TASKBAY_COVERAGE_CHILD then return trace() end -- an editor spawned by a test

if vim.env.TASKBAY_COVERAGE_TEST then -- one traced test process
  trace()
  -- Child editors trace too; the full config runs slower under the hook, so RPCs get more time.
  local spawn = vim.uv.spawn
  vim.uv.spawn = function(cmd, opts, ...)
    if cmd == "nvim" and opts and opts.args then
      table.insert(opts.args, 1, "--cmd")
      table.insert(opts.args, 2, "lua dofile(" .. vim.inspect(self_path) .. ")")
      if not opts.env then
        opts.env = {}
        for key, value in pairs(vim.fn.environ()) do opts.env[#opts.env + 1] = key .. "=" .. value end
      end
      vim.list_extend(opts.env, { "TASKBAY_COVERAGE_CHILD=1", "TASKBAY_COVERAGE_OUT=" .. out })
    end
    return spawn(cmd, opts, ...)
  end
  local load = dofile
  _G.dofile = function(path, ...)
    local result = load(path, ...)
    if type(path) == "string" and path:match("tests/harness%.lua$") then
      return function(o) return result(vim.tbl_extend("force", o or {}, { rpc_timeout = 60000 })) end
    end
    return result
  end
  return dofile(vim.env.TASKBAY_COVERAGE_TEST)
end

-- Runner: trace every test, then report per module against the lines LuaJIT emits code for.
local tests = loadfile(vim.fs.dirname(self_path) .. "/run.lua")("list")
out = vim.fn.tempname()
local failed = {}
for _, test in ipairs(tests) do
  local result = vim.system({ "nvim", "--headless", "-u", "NONE", "-i", "NONE", "-l", self_path }, {
    env = { TASKBAY_COVERAGE_TEST = vim.fs.dirname(self_path) .. "/" .. test .. ".lua", TASKBAY_COVERAGE_OUT = out },
  }):wait()
  if result.code ~= 0 then failed[#failed + 1] = test .. ": " .. vim.trim(result.stderr or ""):sub(-300) end
end
local hits = {}
for _, key in ipairs(vim.fn.readfile(out)) do hits[key] = true end
local ju = require("jit.util")
local total, covered = 0, 0
for _, name in ipairs({ "init", "core", "ui", "review", "remote", "store", "editor", "fields", "terminal", "remotes/github",
  "agents/pi" }) do
  local path = vim.fs.dirname(vim.fs.dirname(self_path)) .. "/lua/taskbay/" .. name .. ".lua"
  local source, lines = vim.fn.readfile(path), {}
  local function walk(fn)
    for pc = 0, math.huge do
      local info = ju.funcinfo(fn, pc)
      if not info.currentline then break end
      lines[info.currentline] = true
    end
    for k = -1, -math.huge, -1 do
      local constant = ju.funck(fn, k)
      if constant == nil then break end
      if type(constant) == "proto" then walk(constant) end
    end
  end
  walk(assert(loadfile(path)))
  local missed = {}
  for line in pairs(lines) do
    local text = vim.trim(source[line] or "")
    -- Skip block ends and declaration lines, which carry no statement of their own.
    local statement = text ~= "" and not text:match("^end[,)]*$") and not text:match("^else$")
      and not text:match("^[})][,)]*$") and not text:match("^%-%-") and not text:match("^local function ")
      and not text:match("^function ") and not text:match("= function%(") and not text:match("^return function%(")
    if statement then
      total = total + 1
      if hits[name .. ":" .. line] then covered = covered + 1 else missed[#missed + 1] = line end
    end
  end
  table.sort(missed)
  print(("%-16s %s"):format(name, #missed == 0 and "100%" or ("missed lines " .. table.concat(missed, ", "))))
end
print(("total %d/%d lines (%.1f%%)"):format(covered, total, 100 * covered / total))
if #failed > 0 then print("failed under tracing:\n" .. table.concat(failed, "\n")) end
vim.fn.delete(out)
vim.cmd(#failed > 0 and "cquit 1" or "qa!")
