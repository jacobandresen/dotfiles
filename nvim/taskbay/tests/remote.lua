-- A second issue tracker through the driver interface alone: an in-memory driver named
-- "fake" serves import, drafts, fields, publish and export, so nothing above the driver
-- may assume GitHub. Run: timeout 60 nvim --headless -u NONE -i NONE -l tests/remote.lua
local plugin = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(plugin)
vim.g.mapleader = " "
local temp = vim.fn.tempname()
vim.fn.mkdir(temp .. "/repo", "p")
vim.g.taskbay = { state_dir = temp .. "/state", remote = "fake", remote_enabled = true }
_G.LazyVim = { root = setmetatable({}, { __call = function() return temp .. "/repo" end }) }
local messages = {}
vim.notify = function(message) messages[#messages + 1] = tostring(message) end

local issues, updates = {
  [7] = { number = 7, title = "Tracker issue", body = "From the tracker.", url = "https://fake.example/team/proj/7",
    state = "open", labels = { "triage" }, assignees = {}, author = "kim", comments = 2, raw = { iid = 7, extra = "kept" } },
}, {}
package.loaded["taskbay.remotes.fake"] = {
  title = "Fake", glyph = "F",
  repository = function(root)
    local repo = require("taskbay.store").checkout(root)
    repo.repo, repo.host = "team/proj", "fake.example"
    return repo
  end,
  list = function() return { issues[7] } end,
  get = function(target) return vim.deepcopy(assert(issues[target.number], "no issue " .. target.number)) end,
  update = function(target, title, body, changes)
    updates[#updates + 1] = { number = target.number, title = title, body = body, changes = changes }
    issues[target.number].title, issues[target.number].body = title, body
  end,
  create = function(repo, title, body)
    issues[8] = { number = 8, title = title, body = body, state = "open", labels = {}, assignees = {} }
    return { source = "fake", host = repo.host, repo = repo.repo, number = 8, title = title, url = "https://fake.example/8" }
  end,
}
local core, tasks, ui = require("taskbay.core"), require("taskbay.store"), require("taskbay.ui")
local editor, fields = require("taskbay.editor"), require("taskbay.fields")
local choice
core.choose = function(items) return choice or items[2] end
local function await(fn)
  local done, failure
  core.task(function()
    local ok, err = pcall(fn)
    done, failure = true, not ok and err or nil
  end)
  assert(vim.wait(10000, function() return done end, 10), table.concat(messages, "\n"))
  assert(not failure, failure)
end
local function last(text) return messages[#messages]:find(text, 1, true) ~= nil end

local ok, failure = xpcall(function()
  for _, args in ipairs({ { "init", "-b", "main" }, { "config", "user.name", "Test" },
    { "config", "user.email", "test@example.invalid" }, { "commit", "--allow-empty", "-m", "Initial" } }) do
    await(function() core.git(temp .. "/repo", unpack(args)) end)
  end
  assert(core.remote().title == "Fake", "remote picks the configured driver")

  -- A draft of a tracker issue: Fields show the normalised issue, publish sends driver changes.
  local target = { source = "fake", host = "fake.example", repo = "team/proj", number = 7, path = temp .. "/repo" }
  editor.open(target)
  await(function() end)
  assert(vim.wo.winbar:find("F Fake draft", 1, true), vim.wo.winbar)
  local draft = vim.api.nvim_get_current_buf()
  await(function() fields.open(target) end)
  local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  assert(text:find("labels: triage", 1, true) and text:find("author: kim", 1, true)
    and text:find("comments: 2", 1, true), text)
  vim.api.nvim_buf_set_lines(0, 2, 3, false, { "labels: triage, ui" })
  vim.cmd("silent write")
  await(function() end)
  vim.api.nvim_set_current_buf(draft)
  choice = "Publish title, body and fields"
  editor.publish(draft)
  await(function() end)
  assert(#updates == 1 and updates[1].changes.add_labels[1] == "ui" and last("Published fake.example/team/proj#7"),
    vim.inspect(updates) .. table.concat(messages, "\n"))

  -- Import copies the issue into a local task; its sidecar keeps the driver's raw data.
  choice = "Import as local task"
  await(function() require("taskbay.remote").import_issues(core.repository(temp .. "/repo", "fake"), { { number = 7 } }) end)
  assert(vim.wait(5000, function() return last("Imported 1 issue(s)") end, 10), table.concat(messages, "\n"))
  local imported
  await(function() imported = tasks.list(core.repository(temp .. "/repo"))[1] end)
  local meta = tasks.get_meta(imported)
  assert(meta.origin == "fake.example/team/proj#7" and meta.issue.extra == "kept" and meta.details.author == "kim"
    and meta.labels[1] == "triage", vim.inspect(meta))

  -- Export publishes a local task as a new tracker issue.
  choice = "Create Fake issue"
  await(function() require("taskbay.remote").export_task(imported) end)
  assert(vim.wait(5000, function() return last("Created team/proj#8") end, 10), table.concat(messages, "\n"))
  assert(issues[8].title == imported.title, vim.inspect(issues[8]))
end, debug.traceback)

vim.fn.delete(temp, "rf")
if not ok then
  io.stderr:write(tostring(failure) .. "\n" .. table.concat(messages, "\n") .. "\n")
  vim.cmd("cquit 1")
end
print("taskbay remote: a second tracker driver serves drafts, fields, publish, import and export")
vim.cmd("qa!")
