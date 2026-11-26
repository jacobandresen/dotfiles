-- End-to-end GitHub flow with real keystrokes against an offline gh stand-in that accepts
-- only what the real gh CLI accepts: enable the integration, browse and view issues, edit a
-- draft and its fields, publish, import an issue as a local task, edit its fields, export it.
-- Run: timeout 180 nvim --headless -u NONE -i NONE -l tests/github.lua
local plugin = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local H = dofile(plugin .. "/tests/harness.lua")({ name = "taskbay-github" })
local lua, keys, wait_for, pick, step, sh = H.lua, H.keys, H.wait_for, H.pick, H.step, H.sh

local gh_dir = H.temp .. "/gh"
vim.fn.mkdir(gh_dir, "p")
vim.fn.writefile({ vim.json.encode({ issues = {
  ["1"] = {
    number = 1, title = "Fix login", body = "Login fails.", state = "OPEN", url = "https://github.com/octo/project/issues/1",
    labels = { { name = "bug" } }, assignees = { { login = "kate" } }, milestone = { title = "v1" },
    comments = { { author = { login = "kate" }, body = "Seen on mobile" } }, createdAt = "2026-01-01T00:00:00Z",
  },
  ["2"] = {
    number = 2, title = "Add dark mode", body = "Users want it.", state = "OPEN", url = "https://github.com/octo/project/issues/2",
    labels = {}, assignees = {}, comments = {},
  },
} }) }, gh_dir .. "/issues.json")
vim.fn.writefile({ "#!/bin/sh", "GH_STUB_DIR=" .. vim.fn.shellescape(gh_dir) .. " exec python3 "
  .. vim.fn.shellescape(plugin .. "/tests/fixtures/gh_stub.py") .. ' "$@"' }, H.temp .. "/bin/gh")
assert(vim.uv.fs_chmod(H.temp .. "/bin/gh", 493))
local function issue(number)
  return vim.json.decode(table.concat(vim.fn.readfile(gh_dir .. "/issues.json"), "\n")).issues[tostring(number)]
end
local function calls(verb)
  local found = {}
  for _, line in ipairs(vim.fn.filereadable(gh_dir .. "/calls.jsonl") == 1 and vim.fn.readfile(gh_dir .. "/calls.jsonl") or {}) do
    local argv = vim.json.decode(line).argv
    if argv[2] == verb then found[#found + 1] = argv end
  end
  return found
end
local function message(text) return "return table.concat(_G.e2e_messages, '\\n'):find(" .. vim.inspect(text) .. ", 1, true) ~= nil" end
-- Confirmations are vim.ui.select pickers; wait until one offers the choice, then take it.
local function confirm(filter, choice)
  wait_for("A confirmation offers " .. choice, [[
    local p = Snacks.picker.get()[1]
    if not p then return false end
    for _, item in ipairs(p:items()) do
      if tostring(item.text):find(..., 1, true) then return true end
    end
    return false
  ]], 15000, choice)
  pick(filter, choice)
end
local function panel()
  keys("<Esc><Space>aw")
  wait_for("Space a w opens the panel", "return e2e.float_lines('Task Workspaces') ~= nil")
end

H.run("taskbay github: enabled, browsed, viewed, edited fields, published, imported, exported, disabled", function()
  H.boot()

  step("GitHub is off by default")
  panel()
  lua([[assert(vim.fn.maparg("I", "n") == "" and vim.fn.maparg("e", "n") == "", "No GitHub keys while it is off")]])
  keys("q:TaskbayImport<CR>")
  wait_for("Import explains that GitHub is off", message("GitHub integration is disabled"))

  step("Space a G turns it on; I lists the open issues")
  keys("<Esc><Space>aG")
  wait_for("Space a G enables GitHub", message("Taskbay GitHub integration enabled"))
  panel()
  keys("I")
  wait_for("I lists the repository's open issues", [[
    local p = Snacks.picker.get()[1]
    return p ~= nil and p:count() == 2 and p.opts.title:find("octo/project / Import GitHub Issues", 1, true) ~= nil
  ]], 15000)
  lua([[
    local texts = vim.tbl_map(function(item) return item.text end, Snacks.picker.get()[1]:items())
    assert(table.concat(texts, "\n"):find("1 Fix login  [bug]", 1, true), table.concat(texts, "\n"))
  ]])

  step("Ctrl-o opens an issue as a local draft; :write never touches GitHub")
  keys("login")
  wait_for("The filter settles on issue 1", "local i = Snacks.picker.get()[1]:current(); return i ~= nil and i.number == 1")
  keys("<C-o>")
  wait_for("Ctrl-o opens the GitHub draft", [[
    local info = vim.b.taskbay_task
    return info ~= nil and info.target.number == 1 and vim.wo.winbar:find("GitHub draft", 1, true) ~= nil
  ]], 15000)
  lua([[assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[3] == "Login fails.", vim.inspect(vim.api.nvim_buf_get_lines(0, 0, -1, false)))]])
  keys("<Esc>Goon every browser<Esc>:write<CR>")
  wait_for("The draft saves locally", "return not vim.bo.modified")
  assert(#calls("edit") == 0 and issue(1).body == "Login fails.", "Saving a draft must not publish it")

  step("Tab opens its Fields; GitHub's OPEN state shows as open and saves")
  keys("<Tab>")
  wait_for("Tab opens the Fields tab", "return vim.api.nvim_buf_get_name(0):find('task://fields/', 1, true) ~= nil")
  lua([[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local text = table.concat(lines, "\n")
    assert(text:find("labels: bug", 1, true) and text:find("assignees: kate", 1, true)
      and text:find("milestone: v1", 1, true) and text:find("state: open", 1, true), text)
    for row, line in ipairs(lines) do
      local replace = ({ labels = "labels: bug, ui", milestone = "milestone: ", state = "state: closed" })[line:match("^(%a+):")]
      if replace then vim.api.nvim_buf_set_lines(0, row - 1, row, false, { replace }) end
    end
  ]])
  keys(":write<CR>")
  wait_for("Fields save locally", message("Saved fields for octo/project#1"))
  assert(#calls("edit") == 0, "Saving Fields must not publish them")

  step("Space a P publishes title, body and field changes with real gh commands")
  keys("<Tab>")
  wait_for("Tab returns to the draft", "return vim.b.taskbay_task ~= nil")
  keys("<Space>aP")
  confirm("fields", "Publish title, body and fields")
  wait_for("The draft is published", message("Published github.com/octo/project#1"), 15000)
  local published = issue(1)
  assert(published.body:find("on every browser", 1, true), vim.inspect(published))
  assert(vim.deep_equal(published.labels, { { name = "bug" }, { name = "ui" } }), vim.inspect(published.labels))
  assert(published.milestone == vim.NIL or published.milestone == nil, vim.inspect(published.milestone))
  assert(published.state == "CLOSED" and #calls("close") == 1, "The state change runs gh issue close")
  assert(vim.tbl_contains(calls("edit")[1], "--remove-milestone"), vim.inspect(calls("edit")))

  step("I imports an issue as a local task with its full snapshot")
  panel()
  keys("I")
  wait_for("Only the open issue is left", "local p = Snacks.picker.get()[1]; return p ~= nil and p:count() == 1", 15000)
  keys("<CR>")
  confirm("Import", "Import as local task")
  wait_for("The issue is imported", message("Imported 1 issue(s) as local task(s)"), 15000)
  local files = vim.fn.readdir(H.repo .. "/.tasks")
  table.sort(files)
  assert(vim.deep_equal(files, { "001-add-dark-mode.md", "001.json" }), vim.inspect(files))
  assert(vim.fn.readfile(H.repo .. "/.tasks/001-add-dark-mode.md")[3] == "Users want it.")
  local meta = vim.json.decode(table.concat(vim.fn.readfile(H.repo .. "/.tasks/001.json"), "\n"))
  assert(meta.origin == "github.com/octo/project#2" and meta.state == "open" and meta.issue.number == 2, vim.inspect(meta))

  step("the imported task's Fields save; e exports it as a new issue")
  panel()
  wait_for("The imported task is a new row", "return e2e.dashboard_row(1) ~= nil")
  lua("vim.api.nvim_win_set_cursor(0, { e2e.dashboard_row(1), 0 })")
  keys("f")
  wait_for("f opens its Fields", "return vim.api.nvim_buf_get_name(0):find('task://fields/', 1, true) ~= nil")
  keys(":write<CR>")
  wait_for("Imported task fields save", message("Saved fields for project/task-1"))
  panel()
  lua("vim.api.nvim_win_set_cursor(0, { e2e.dashboard_row(1), 0 })")
  keys("e")
  confirm("Create", "Create GitHub issue")
  wait_for("e creates a new issue", message("Created octo/project#3"), 15000)
  assert(issue(3).title == "Add dark mode" and issue(3).body == "Users want it.", vim.inspect(issue(3)))

  step(":TaskbayExport exports the task in the current buffer")
  panel()
  lua("vim.api.nvim_win_set_cursor(0, { e2e.dashboard_row(1), 0 })")
  keys("v")
  wait_for("v opens the task text", "local info = vim.b.taskbay_task; return info ~= nil and info.target.number == 1")
  keys(":TaskbayExport<CR>")
  confirm("Create", "Create GitHub issue")
  wait_for("The command creates another issue", message("Created octo/project#4"), 15000)

  step("Space a G turns it off again")
  keys("<Esc><Space>aG")
  wait_for("Space a G disables GitHub", message("Taskbay GitHub integration disabled"))
  panel()
  lua([[assert(vim.fn.maparg("I", "n") == "", "No GitHub keys once it is off")]])
  assert(sh({ "git", "status", "--porcelain" }) == "?? .tasks/", "The main checkout only gains the task store")
end)
