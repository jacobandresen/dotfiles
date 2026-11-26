-- Run: timeout 60 nvim --headless -u NONE -i NONE -l tests/fields.lua
local plugin = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(plugin)
vim.g.mapleader = " "
local core = require("taskbay.core")
local tasks = require("taskbay.store")
local editor = require("taskbay.editor")
local fields = require("taskbay.fields")
local temp = vim.fn.tempname()
vim.fn.mkdir(temp .. "/repo", "p")
vim.g.taskbay = { state_dir = temp .. "/state", remote_enabled = true,
  pi = { cmd = plugin .. "/tests/fixtures/pi_stub.py" } }
_G.LazyVim = { root = setmetatable({}, { __call = function() return temp .. "/repo" end }) }
local messages = {}
vim.notify = function(message) messages[#messages + 1] = tostring(message) end
local choice = "Cancel"
core.choose = function() return choice end

local remote = { title = "Tracked issue", body = "Upstream body", url = "https://github.com/test/repo/issues/42",
  state = "OPEN", milestone = { title = "v1" }, -- gh reports state in capitals
  labels = { { name = "bug" }, { name = "cli" } },
  assignees = { { login = "jacob" } },
  comments = { { author = { login = "kate" }, body = "Original comment" } },
  createdAt = "2025-01-01T00:00:00Z", updatedAt = "2025-01-02T00:00:00Z",
  projectItems = { id = "PVT_1" } }
local original_run = core.run
local edits = {}
core.run = function(argv, cwd, optional, stdin)
  if argv[1] == "gh" then
    if argv[2] == "repo" then
      return { code = 0, stdout = vim.json.encode({
        nameWithOwner = "test/repo", url = "https://github.com/test/repo", defaultBranchRef = { name = "main" },
      }) }
    end
    if argv[3] == "view" then return { code = 0, stdout = vim.json.encode(remote) } end
    assert(vim.tbl_contains({ "edit", "close", "reopen" }, argv[3]), vim.inspect(argv))
    edits[#edits + 1] = { argv = argv, body = stdin }
    return { code = 0, stdout = "updated" }
  end
  return original_run(argv, cwd, optional, stdin)
end
local function await(fn)
  local done, result, failure
  core.task(function()
    local ok, value = pcall(fn)
    done = true
    if ok then result = value else failure = value end
  end)
  assert(vim.wait(15000, function() return done end, 10), table.concat(messages, "\n"))
  assert(not failure, failure)
  return result
end
local function baseline()
  return vim.json.decode(table.concat(vim.fn.readfile(
    temp .. "/state/issue-drafts/" .. vim.fn.sha256("github.com/test/repo#42") .. "/baseline.json"), "\n"))
end

local function boom(err) error(debug.traceback(err), 0) end
local ok, failure = xpcall(function()
  for _, args in ipairs({
    { "init", "-b", "main" }, { "config", "user.name", "Test" },
    { "config", "user.email", "test@example.invalid" },
  }) do await(function() core.git(temp .. "/repo", unpack(args)) end) end
  core.write(temp .. "/repo/code.txt", "Original\n")
  await(function() core.git(temp .. "/repo", "add", "code.txt") end)
  await(function() core.git(temp .. "/repo", "commit", "-m", "Initial") end)
  local repo = await(function() return core.repository(temp .. "/repo") end)

  -- A local task whose sidecar carries an imported-style snapshot and a custom key.
  local task = tasks.create(repo, "Minimal task", "Markdown body only.")
  tasks.set_meta(task, {
    labels = { "bug" }, assignees = { "jacob" }, milestone = "v1", state = "open", relations = {},
    origin = "github.com/test/repo#42",
    details = { author = "jacob", created_at = remote.createdAt, updated_at = remote.updatedAt, comments = 1 },
    issue = { url = remote.url, author = { login = "jacob" },
      labels = { { name = "bug" } }, comments = { { body = "Original comment" } },
      createdAt = remote.createdAt, updatedAt = remote.updatedAt },
    custom_note = "keep me",
  })

  -- Render: editable keys up top, read-only metadata below, no snapshot dump.
  local lines = fields.render(task, fields.fields(task))
  local text = table.concat(lines, "\n")
  for _, needle in ipairs({ "# Fields — repo/1", "labels: bug", "assignees: jacob", "milestone: v1",
    "state: open", "blocked-by:", "origin: github.com/test/repo#42", "author: jacob",
    "created_at: 2025-01-01" }) do
    assert(text:find(needle, 1, true), "Fields render missing '" .. needle .. "':\n" .. text)
  end
  assert(not text:find("Original comment", 1, true), "The fields tab shows counts, not comment bodies")
  -- A sidecar imported before the tracker drivers has only GitHub's raw issue.
  local legacy = tasks.get_meta(task)
  legacy.details = nil
  tasks.set_meta(task, legacy)
  text = table.concat(fields.render(task, fields.fields(task)), "\n")
  assert(text:find("author: jacob", 1, true) and text:find("created_at: 2025-01-01", 1, true), text)

  -- Parsing: keys map to kinds; unknown shapes fail loudly.
  local values = fields.values({
    "labels: ui, bug", "assignees: kate", "milestone:", "state: closed",
    "relates: repo/2-other", "blocks: github.com/test/repo#9, local:/x#3", "blocked-by:", "duplicate-of: #7",
    "---  read only", "origin: github.com/test/repo#42",
  })
  assert(values.labels[1] == "ui" and values.labels[2] == "bug" and #values.assignees == 1
    and values.milestone == nil and values.state == "closed", "Edited values must round-trip")
  assert(#values.relations == 4, vim.inspect(values.relations))
  assert(values.relations[1].kind == "relates" and values.relations[1].target == "repo/2-other")
  assert(values.relations[2].kind == "blocks" and values.relations[3].kind == "blocks"
    and values.relations[3].target == "local:/x#3")
  assert(values.relations[4].kind == "duplicate_of" and values.relations[4].target == "#7")
  local _, err = pcall(fields.values, { "wat" })
  assert(tostring(err):find("key: values", 1, true), tostring(err))
  _, err = pcall(fields.values, { "state: Archived" })
  assert(tostring(err):find("open or closed", 1, true), tostring(err))
  _, err = pcall(fields.values, { "mood: fine" })
  assert(tostring(err):find("Unknown editable field", 1, true), tostring(err))

  -- The Fields tab: open, edit, :write. Sidecar gets the edits; snapshot,
  -- custom keys and Markdown stay put; the Task buffer shows relations.
  editor.open(task)
  local task_buf = vim.api.nvim_get_current_buf()
  await(function() fields.open(task) end)
  assert(vim.b.taskbay_fields_for == tasks.identity(task), "The fields buffer records its task")
  -- Tab flips between Task and Fields from both sides.
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Tab>", true, false, true), "x", false)
  assert(vim.api.nvim_get_current_buf() == task_buf, "Tab in Fields returns to the Task tab")
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Tab>", true, false, true), "x", false)
  assert(vim.wait(2000, function() return vim.b.taskbay_fields_for == tasks.identity(task) end, 10),
    "Tab in the Task tab opens Fields")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "# Fields — " .. tasks.label(task), "",
    "labels: bug, ui", "assignees: kate", "milestone: v1", "state: open",
    "relates: repo/2-fix-kitty-clip", "blocked-by: github.com/test/repo#9",
    "---  read only", "origin: github.com/test/repo#42", "author: jacob", "comments: 1",
  })
  vim.cmd("silent write")
  await(function()
    local saved = tasks.get_meta(task)
    assert(saved.labels[2] == "ui" and saved.assignees[1] == "kate", vim.inspect(saved))
    assert(saved.custom_note == "keep me" and saved.issue.comments[1].body == "Original comment",
      "Fields edits must not drop the snapshot or custom keys")
    assert(saved.relations[1].kind == "relates" and saved.relations[2].kind == "blocked_by",
      vim.inspect(saved.relations))
  end)
  await(function() fields.open(task) end)
  assert(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("labels: bug, ui", 1, true),
    "Reopening renders the saved fields")
  local decoration = vim.api.nvim_buf_get_extmarks(task_buf, vim.api.nvim_create_namespace("taskbay_relations"),
    0, -1, { details = true })
  assert(#decoration == 1, "The Task buffer must show one relation block")
  local text_of = function(line)
    local out = {}
    for _, segment in ipairs(line) do out[#out + 1] = segment[1] or "" end
    return table.concat(out)
  end
  local shown = vim.tbl_map(text_of, decoration[1][4].virt_lines)
  assert(#shown == 2, vim.inspect(shown))
  assert(shown[1]:find("relates to repo/2-fix-kitty-clip", 1, true)
    and shown[2]:find("blocked by github.com/test/repo#9", 1, true),
    "Relations must render with their kind text, in saved order: " .. vim.inspect(shown))

  -- GitHub draft: Fields edits overlay the baseline; publish pushes only diffs.
  local target = { source = "github", host = "github.com", repo = "test/repo", number = 42, path = temp }
  editor.open(target)
  await(function() end)
  await(function() fields.open(target) end)
  assert(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("labels: bug, cli", 1, true),
    "The draft's Fields tab shows the issue's current labels")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, {
    "# Fields — " .. tasks.label(target), "",
    "labels: bug, ui", "assignees: jacob, kate", "milestone: v1", "state: closed",
    "relates:", "blocks: repo/3-third", "blocked-by:", "duplicate-of:",
    "---  read only", "origin: github.com/test/repo#42", "comments: 1",
  })
  vim.cmd("silent write")
  await(function()
    local base = baseline()
    assert(base.fields.labels[2] == "ui" and base.fields.state == "closed", vim.inspect(base.fields))
    assert(base.issue.raw.labels[1].name == "bug" and base.issue.raw.labels[2].name == "cli",
      "The overlay must never rewrite or drop the issue snapshot")
    assert(#edits == 0, "Saving Fields locally must not touch GitHub")
  end)
  assert(editor.field_diffs(nil, remote) == nil, "No overlay means no field diffs")
  local diffs = editor.field_diffs(baseline().fields, baseline().issue)
  assert(diffs and diffs.add_labels[1] == "ui" and diffs.remove_labels[1] == "cli"
    and diffs.add_assignees[1] == "kate" and #diffs.remove_assignees == 0 and diffs.state == "closed"
    and diffs.milestone == nil, "Only real changes become gh flags: " .. vim.inspect(diffs))
  local summary = table.concat(editor.field_changes(diffs) or {}, ", ")
  assert(summary:find("+label ui", 1, true), "Unexpected field-change summary: " .. summary)

  -- Publish pushes title, body and the field diffs, then clears the overlay.
  await(function()
    fields.close(target) -- back to the Task tab; publish acts on the task buffer
    assert(vim.b.taskbay_task and vim.b.taskbay_task.target.number == 42, "q / Space af returns to the Task tab")
    assert(vim.api.nvim_buf_get_name(0):find("%.md$", 1, true) == nil or vim.fn.filereadable(vim.api.nvim_buf_get_name(0)) == 1,
      "The task buffer exists")
  end)
  choice = "Publish title, body and fields"
  editor.publish(vim.api.nvim_get_current_buf())
  await(function() end)
  -- gh issue edit has no state flag: the state change is a separate gh issue close.
  assert(#edits == 2 and edits[2].argv[3] == "close" and edits[2].argv[4] == "42", vim.inspect(edits))
  local edit = edits[1].argv
  assert(vim.tbl_contains(edit, "--title") and edits[1].body == "Upstream body", vim.inspect(edit))
  assert(vim.tbl_contains(edit, "--add-label") and vim.tbl_contains(edit, "ui"), vim.inspect(edit))
  assert(vim.tbl_contains(edit, "--remove-label") and vim.tbl_contains(edit, "cli"), vim.inspect(edit))
  assert(vim.tbl_contains(edit, "--add-assignee") and vim.tbl_contains(edit, "kate"), vim.inspect(edit))
  assert(not vim.tbl_contains(edit, "--state"), vim.inspect(edit))
  assert(not vim.tbl_contains(edit, "--remove-assignee") and not vim.tbl_contains(edit, "--milestone"),
    "Unchanged fields must not be pushed")
  local base = baseline()
  assert(base.fields == nil, "A successful publish clears the fields overlay")
  assert(base.issue.raw.labels[1].name == "bug" and base.issue.raw.comments[1].body == "Original comment",
    "Publish must keep the original snapshot intact")

  -- Edge cases: no task, no baseline yet, untouched fields, removed assignees,
  -- reloading a loaded draft and returning to a draft that is not loaded.
  local function last(pattern) return messages[#messages]:find(pattern, 1, true) ~= nil end
  vim.cmd.tabnew()
  editor.open()
  assert(last("Choose a task in Space a w first"))
  fields.open({ source = "github", host = "github.com", repo = "test/repo", number = 99, path = temp })
  assert(last("Open the issue first"), "GitHub fields need the draft's baseline")
  assert(editor.field_diffs({}, {}) == nil, "Untouched fields produce no gh flags")
  edits = {}
  assert(editor.field_changes({ milestone = "" })[1] == "milestone (none)", "A cleared milestone reads as none")
  await(function() tasks.update(target, "T", "B", { milestone = "", state = "open" }) end)
  assert(vim.tbl_contains(edits[1].argv, "--remove-milestone") and not vim.tbl_contains(edits[1].argv, "--milestone")
    and edits[2].argv[3] == "reopen", "A cleared milestone and a reopened state use gh's own commands: " .. vim.inspect(edits))
  edits = {}
  await(function() tasks.update(target, "T", "B", { remove_assignees = { "jacob" } }) end)
  assert(vim.tbl_contains(edits[1].argv, "--remove-assignee"), vim.inspect(edits))
  editor.open(target)
  await(function() end)
  choice = "Replace local draft"
  editor.open(target, true)
  await(function() end)
  assert(vim.b.taskbay_task and vim.b.taskbay_task.target.number == 42, "Reload keeps the draft open")
  vim.cmd("silent! %bwipeout!")
  fields.close(target)
  await(function() end)
  assert(vim.b.taskbay_task and vim.b.taskbay_task.target.number == 42, "Closing Fields reopens an unloaded draft")
  -- Saving a task's fields refreshes its workspace row.
  local changed = core.changed
  local refreshed
  core.changed = function() refreshed = true end
  core.workspaces.probe = vim.deepcopy(task)
  await(function() fields.open(task) end)
  vim.cmd("silent write")
  assert(vim.wait(3000, function() return refreshed end, 10), "Saving fields refreshes the task's workspace")
  core.workspaces.probe, core.changed = nil, changed
end, function(e) return debug.traceback(e) end)

vim.fn.delete(temp, "rf")
if not ok then
  io.stderr:write(debug.traceback(failure) .. "\n\nTRACEBACK:\n" .. tostring(failure) .. "\n")
  vim.cmd("cquit 1")
end
print("taskbay fields: minimal task view, sidecar edits, snapshot intact, publish diffs passed")
vim.cmd("qa!")
