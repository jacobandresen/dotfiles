-- Run: timeout 60 nvim --headless -u NONE -i NONE -l tests/tasks.lua
local plugin = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(plugin)
vim.g.mapleader = " "
local core = require("taskbay.core")
local tasks = require("taskbay.store")
local editor = require("taskbay.editor")
local temp = vim.fn.tempname()
vim.fn.mkdir(temp .. "/repo", "p")
vim.g.taskbay = { state_dir = temp .. "/state", pi = { cmd = plugin .. "/tests/fixtures/pi_stub.py" } }
local messages = {}
vim.notify = function(message) messages[#messages + 1] = tostring(message) end
_G.LazyVim = { root = setmetatable({ detectors = {}, cache = {} }, {
  __call = function() return temp .. "/repo" end,
}) }
local run = core.run
core.run = function(argv, ...)
  assert(argv[1] ~= "gh", "Local tasks must never invoke gh")
  return run(argv, ...)
end
local function await(fn)
  local done, result, failure = false
  core.task(function()
    local ok, value = pcall(fn)
    if ok then result = value else failure = value end
    done = true
  end)
  assert(vim.wait(15000, function() return done end, 10), table.concat(messages, "\n"))
  assert(not failure, failure)
  return result
end
local function expect_error(fn, pattern)
  local ok, err = pcall(fn)
  assert(not ok and tostring(err):find(pattern, 1, true), tostring(err))
end
local function git(...)
  local args = { ... }
  return vim.trim(await(function() return core.git(temp .. "/repo", unpack(args)) end))
end

local ok, failure = xpcall(function()
  git("init", "-b", "main")
  git("config", "user.name", "Test")
  git("config", "user.email", "test@example.invalid")
  core.write(temp .. "/repo/code.txt", "Original\n")
  git("add", "code.txt")
  git("commit", "-m", "Initial")
  local repo = await(function() return core.repository(temp .. "/repo") end)
  assert(repo.source == "local" and repo.task_root == temp .. "/repo")
  for _, source in ipairs({ "other", false }) do
    expect_error(function() tasks.repository(repo.root, source) end, "Unknown task source")
  end
  for _, number in ipairs({ 0, -1, 1.5, 9007199254740992, math.huge }) do
    expect_error(function() tasks.identity({ source = "local", task_root = repo.root, number = number }) end,
      "positive safe integer")
  end
  assert(tasks.identity({ source = "local", task_root = repo.root, number = 1000000000000001 })
    ~= tasks.identity({ source = "local", task_root = repo.root, number = 1000000000000002 }),
    "Large valid task IDs must not collide through scientific notation")
  for _, lines in ipairs({ {}, { "# ", "", "Body" }, { "Title", "", "Body" }, { "# Title", "Body" } }) do
    expect_error(function() tasks.parse(lines) end, "Keep '# Title'")
  end
  local progress = tasks.actions({ body = "Intro\n- [ ] first\n- [x] second\n* [x] third\n- [ ]\n- plain line" })
  assert(progress.done == 2 and progress.total == 4, vim.inspect(progress))
  assert(tasks.actions({ body = "no checklist" }).total == 0, "Tasks may have no action list")
  for _, fn in ipairs({
    function() tasks.repository(repo.root, "github") end,
    function() tasks.list({ host = "github.com", repo = "test/repo", root = repo.root }) end,
    function() tasks.get({ host = "github.com", repo = "test/repo", number = 1, path = repo.root }) end,
    function() tasks.update({ host = "github.com", repo = "test/repo", number = 1, path = repo.root }, "Title", "Body") end,
    function() tasks.create({ host = "github.com", repo = "test/repo", root = repo.root }, "Title", "Body") end,
  }) do expect_error(fn, "issue tracker integration is disabled") end
  local a = tasks.create(repo, "Improve search")
  local b = tasks.create(repo, "Fix login")
  assert(a.number == 1 and b.number == 2 and a.task_file == "001-improve-search.md")
  assert(tasks.get(a).body == "", "New tasks must not insert boilerplate")
  local body = "Status: active\n\n## Acceptance criteria\n\n- [ ] Resume reliably."
  tasks.update(a, "Resumable search", body)
  assert(tasks.get(a).title == "Resumable search" and tasks.get(a).body == body)
  local matches = tasks.list(repo, "RESUME", 50)
  assert(#matches == 1 and matches[1].number == a.number, "Search titles and bodies locally")
  assert(#tasks.list(repo, "", 1) == 1)
  expect_error(function() tasks.create(repo, "Title\nwith newline") end, "single-line")
  expect_error(function() tasks.update(a, "Title\nwith newline", "Invalid") end, "single-line")
  assert(tasks.get(a).body == body, "Invalid updates must leave task files intact")
  local duplicate = repo.root .. "/.tasks/001-duplicate.md"
  core.write(duplicate, "# Duplicate\n\nBody\n")
  expect_error(function() tasks.create(repo, "Another") end, "duplicate local task ID")
  assert(not vim.uv.fs_stat(repo.root .. "/.tasks/.create.lock"), "Creation failures release their lock")
  assert(vim.uv.fs_unlink(duplicate))
  -- Metadata sidecar: '.tasks/NNN.json' keeps the Markdown file minimal while
  -- storing the imported snapshot, editable fields and relations.
  local meta = { labels = { "bug", "cli" }, assignees = { "jacob" }, milestone = "v1",
    state = "open", relations = { { kind = "relates", target = "github.com/test/repo#42" } },
    origin = "github.com/test/repo#42", issue = { body = "snapshot", comments = { { body = "C" } },
      labels = { { name = "bug" } }, title = "Imported issue", url = "https://github.com/test/repo/issues/42" } }
  local c = tasks.create(repo, "Imported issue", "Snapshot below.")
  tasks.set_meta(c, meta)
  local read_back = tasks.get_meta(c)
  assert(read_back.labels[2] == "cli" and read_back.issue.comments[1].body == "C",
    "The sidecar round-trips its snapshot and fields")
  assert(tasks.get(c).meta.labels[2] == "cli", "get() exposes the sidecar as .meta")
  tasks.update(c, "Renamed import", "Edited body")
  read_back = tasks.get_meta(c)
  assert(tasks.get(c).title == "Renamed import" and tasks.get(c).body == "Edited body")
  assert(read_back.assignees[1] == "jacob" and read_back.issue.title == "Imported issue",
    "Local edits must keep the stored issue snapshot and metadata intact")
  assert(read_back.relations[1].target == "github.com/test/repo#42", "Relations round-trip")
  tasks.set_meta(c, {}) -- empty metadata removes the sidecar
  assert(not vim.uv.fs_stat(tasks.meta_path(c)), "Empty metadata must remove the sidecar")
  core.write(tasks.meta_path(c), "{ not json }")
  expect_error(function() tasks.get_meta(c) end, "one JSON object")
  assert(vim.uv.fs_unlink(tasks.meta_path(c)))
  core.write(repo.root .. "/.tasks/999.json", "{}")
  expect_error(function() tasks.list(repo) end, "metadata 999.json has no")
  assert(vim.uv.fs_unlink(repo.root .. "/.tasks/999.json"))
  assert(next(tasks.get(a).meta) == nil, "Tasks without a sidecar read as empty metadata")
  tasks.delete(c)
  assert(#tasks.list(repo) == 2 and vim.uv.fs_stat(repo.root .. "/.tasks/002-fix-login.md"))
  assert(not vim.uv.fs_stat(repo.root .. "/.tasks/003.json"), "Deleting a task removes its metadata")
  -- A deleted task must not resolve again from its remembered filename.
  expect_error(function() tasks.get(c) end, "does not match")
  expect_error(function() tasks.meta_path(c) end, "does not match")
  -- A forgotten filename (renamed on disk elsewhere) is re-scanned by ID.
  local stale = tasks.get(vim.tbl_extend("force", a, { task_file = "001-improve-search.md" }))
  assert(stale.title == "Resumable search", "A stale remembered filename must be re-scanned by its ID")
  local invalid = repo.root .. "/.tasks/9007199254740992-too-large.md"
  core.write(invalid, "# Invalid\n\nBody\n")
  expect_error(function() tasks.list(repo) end, "Invalid task ID")
  assert(vim.uv.fs_unlink(invalid))
  core.write(temp .. "/outside.md", "# Outside\n\nDo not edit\n")
  local escape = repo.root .. "/.tasks/999-escape.md"
  assert(vim.uv.fs_symlink(temp .. "/outside.md", escape))
  expect_error(function()
    tasks.get(vim.tbl_extend("force", a, { number = 999, task_file = "999-escape.md" }))
  end, "stay inside .tasks")
  assert(vim.uv.fs_unlink(escape))
  expect_error(function()
    tasks.get(vim.tbl_extend("force", a, { task_file = "../001-improve-search.md" }))
  end, "does not match")

  local workspace = await(function() return core.prepare(repo, a, "HEAD", true) end)
  assert(workspace.branch == "task/1" and workspace.path:match("/task%-1$"))
  assert(workspace.source == "local" and workspace.task_root == repo.root)
  assert(workspace.task_file == a.task_file and tasks.identity(workspace) == tasks.identity(a))
  local github = { source = "github", host = "github.com", repo = "test/repo", root = repo.root, common = repo.common }
  expect_error(function() core.prepare(github, { number = 1, title = "GitHub issue" }, "HEAD", true) end, "disabled")
  vim.g.taskbay = vim.tbl_extend("force", vim.g.taskbay, { remote_enabled = true })
  local github_workspace = await(function()
    return core.prepare(github, { number = 1, title = "GitHub issue" }, "HEAD", true)
  end)
  vim.g.taskbay = vim.tbl_extend("force", vim.g.taskbay, { remote_enabled = false })
  assert(workspace.id ~= github_workspace.id and workspace.path ~= github_workspace.path,
    "A local task and GitHub issue with the same number must have distinct worktrees")
  assert(not vim.uv.fs_stat(workspace.path .. "/.tasks"), "Untracked task files are not copied into worktrees")
  local from_worktree = await(function() return core.repository(workspace.path) end)
  assert(from_worktree.root == repo.root and tasks.list(from_worktree)[1].title == "Resumable search")
  core.setup()
  core.open(workspace)
  await(function() core.start(workspace) end)
  local job = core.jobs[workspace.id]
  assert(vim.wait(5000, function() return job.sequence ~= nil end, 10), table.concat(messages, "\n"))
  assert(job.model == "ollama/mellum")
  local attachment
  for _, arg in ipairs(job.argv) do
    if arg:sub(1, 1) == "@" then attachment = arg:sub(2) end
  end
  assert(attachment and table.concat(vim.fn.readfile(attachment), "\n"):find("Resume reliably.", 1, true),
    "Load local task context when starting pi")
  assert(table.concat(vim.fn.readfile(attachment), "\n"):find("Actions checklist", 1, true),
    "The task prompt explains the action list workflow")
  assert(not vim.tbl_contains(job.argv, "--model"), "Local tasks inherit pi-agent model settings")
  assert(vim.tbl_contains(job.argv, "Implement the attached task."))
  editor.open()
  local buf = vim.api.nvim_get_current_buf()
  assert(vim.api.nvim_buf_get_name(buf) == tasks.file(a), "Edit the canonical task, not a stale worktree copy")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# Search checkpoint", "", "Status: active", "", "- [ ] Next step" })
  vim.cmd("silent write")
  assert(vim.wait(3000, function()
    return vim.api.nvim_buf_is_valid(buf)
      and vim.api.nvim_buf_get_name(buf):find("001%-search%-checkpoint%.md$") ~= nil
  end, 10), "Task title rename did not settle")
  assert(tasks.get(a).title == "Search checkpoint" and workspace.title == "Search checkpoint")
  local sent, send = nil, vim.api.nvim_chan_send
  vim.api.nvim_chan_send = function(channel, text)
    assert(channel == job.channel)
    sent = text
  end
  core.input = function() return "Break the remaining work into smaller steps." end
  editor.agent(buf)
  vim.api.nvim_chan_send = send
  assert(sent and sent:find("Edit only the local task file", 1, true) and sent:find(tasks.file(a), 1, true))
  tasks.update(a, "External checkpoint", body)
  await(function() core.refresh(workspace) end)
  assert(workspace.title == "External checkpoint", "Refresh local titles after pi edits the source file")
  editor.publish(buf)
  assert(messages[#messages]:find("nothing to publish", 1, true))
  core.stop(workspace)
  assert(vim.wait(4000, function() return job.exited end, 10))
  await(function() core.start(workspace) end)
  local resumed = core.jobs[workspace.id]
  assert(vim.tbl_contains(resumed.argv, "--session") and not vim.tbl_contains(resumed.argv, "Implement the attached task."))
  core.stop(workspace)
  assert(vim.wait(4000, function() return resumed.exited end, 10))
  -- A restart opens a new conversation; its prompt must tell pi to pick up where the previous left off.
  await(function() core.restart(workspace) end)
  local restarted = core.jobs[workspace.id]
  local restart_attachment
  for _, arg in ipairs(restarted.argv) do
    if arg:sub(1, 1) == "@" then restart_attachment = arg:sub(2) end
  end
  assert(restart_attachment
    and table.concat(vim.fn.readfile(restart_attachment), "\n"):find("previous conversation already worked", 1, true),
    "A restarted task instructs pi to pick up the existing worktree work")
  core.stop(workspace)
  assert(vim.wait(4000, function() return restarted.exited end, 10))
  local restored = dofile(vim.api.nvim_get_runtime_file("lua/taskbay/core.lua", false)[1])
  restored.load()
  assert(restored.workspaces[workspace.id].task_file == a.task_file)
  assert(tasks.get(restored.workspaces[workspace.id]).title == "External checkpoint")
  assert(next(restored.jobs) == nil, "Restoring local task metadata must not start agents")

  vim.opt.rtp:append(vim.env.TASKBAY_SNACKS or (vim.fn.stdpath("data") .. "/lazy/snacks.nvim"))
  _G.Snacks = require("snacks")
  Snacks.setup({ picker = { enabled = true }, notifier = { enabled = false } })
  local ui = require("taskbay.ui")
  ui.setup()
  -- GitHub keys exist (and appear in which-key) only while the integration is on.
  local function dash_buf()
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(b):find("^taskbay://panel/", 1, false) then return b end
    end
  end
  local function dash_desc(key)
    local buffer = dash_buf()
    vim.api.nvim_set_current_win(vim.fn.win_findbuf(buffer)[1])
    local mapping = vim.fn.maparg(key, "n", false, true)
    return type(mapping) == "table" and mapping.desc or "missing"
  end
  local function dash_footer()
    local win = vim.fn.win_findbuf(dash_buf())[1]
    local footer = vim.api.nvim_win_get_config(win).footer or ""
    if type(footer) == "table" then
      footer = table.concat(vim.tbl_map(function(chunk)
        return type(chunk) == "table" and chunk[1] or tostring(chunk)
      end, footer))
    end
    return footer
  end
  assert(core.settings().remote_enabled == false, "Tests run with the GitHub integration off")
  ui.dashboard()
  assert(dash_desc("e") == "missing" and dash_desc("I") == "missing" and dash_desc("g") == "missing",
    "The dashboard must not map GitHub actions while the integration is off")
  assert(dash_footer():find("export", 1, true) == nil and dash_footer():find("? help", 1, true),
    ("The footer must not list GitHub actions while the integration is off (footer=%s)"):format(dash_footer()))
  -- The footer lists only what the selected row can do: here a stopped workspace.
  assert(dash_footer():find("R restart", 1, true) and dash_footer():find("m finish", 1, true)
    and dash_footer():find("x stop", 1, true) == nil,
    ("The footer must follow the selected row (footer=%s)"):format(dash_footer()))
  assert(dash_desc("m") == "Finish: Commit, Merge, Mark Finished" and dash_desc("d") == "Working Diff"
    and dash_desc("p") == "Start / Resume Agent", "Dashboard keys carry descriptions")
  for _, key in ipairs({ "a", "E", "Q", "i", "g" }) do
    assert(dash_desc(key) == "missing", "Duplicate or hint key must not be mapped: " .. key)
  end
  local panel_win = vim.api.nvim_get_current_win()
  vim.fn.feedkeys("?", "xt")
  local help_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  assert(help_text:find("n  new task", 1, true) and help_text:find("GitHub is off", 1, true),
    "The help lists creation and says how to enable GitHub")
  vim.fn.feedkeys("q", "xt")
  assert(vim.api.nvim_get_current_win() == panel_win, "Closing the help returns to the panel")
  -- Space a s appears only while pi runs, Space a v / r only while a task is
  -- selected; actions owned by the panel are never mapped globally.
  local expect_map = core.live() > 0
  local expect_task = core.current() ~= nil or (vim.b.taskbay_task or {}).target ~= nil
  local function maps_follow(task)
    for _, map in ipairs({ { "<leader>as", expect_map }, { "<leader>av", task }, { "<leader>ar", task },
      { "<leader>aa", false }, { "<leader>ag", false }, { "<leader>ae", false }, { "<leader>af", false },
      { "<leader>aR", false }, { "<leader>am", false } }) do
      if (vim.fn.maparg(map[1], "n") ~= "") ~= map[2] then return false end
    end
    return true
  end
  assert(vim.wait(4000, function() return maps_follow(expect_task) end, 20),
    "The pi key mappings must follow the running-agent and task-selection state")
  -- In a tab with no current task the task keys must disappear.
  vim.cmd.tabnew()
  vim.cmd.enew()
  local unselected_ok = vim.wait(4000, function() return maps_follow(false) end, 20)
  vim.cmd.tabclose()
  assert(unselected_ok, "Task command mappings must be absent when no task is selected")
  ui.toggle_remote()
  assert(core.settings().remote_enabled and not vim.api.nvim_buf_is_valid(dash_buf() or -1),
    "Toggling must close a stale dashboard so its keys rebuild")
  ui.dashboard()
  assert(dash_desc("e") == "Export to a New GitHub Issue" and dash_desc("I") == "Import GitHub Issues",
    ("The dashboard maps GitHub actions with descriptions while the integration is on (e=%s I=%s)")
      :format(dash_desc("e"), dash_desc("I")))
  assert(dash_desc("g") == "missing" and dash_desc("i") == "missing",
    "The dashboard must not offer a task or GitHub issue picker (panel-only selection)")
  ui.toggle_remote() -- restore the off state for the rest of the suite
  assert(core.settings().remote_enabled == false)
  ui.dashboard()
  assert(vim.wait(5000, function()
    local buffer = dash_buf()
    return buffer ~= nil and #vim.fn.win_findbuf(buffer) > 0 and vim.api.nvim_buf_line_count(buffer) > 4
  end, 10), table.concat(messages, "\n"))
  -- Tasks are selected from the workspace panel rows only; v views the row's task.
  vim.fn.feedkeys("v", "xt")
  assert(vim.wait(3000, function()
    return vim.b.taskbay_task and vim.b.taskbay_task.target.source == "local"
  end, 10))
  vim.cmd("TaskbayNew Review the remaining tests")
  assert(vim.wait(5000, function()
    return vim.b.taskbay_task and vim.b.taskbay_task.target.number == 3
  end, 10), table.concat(messages, "\n"))
  assert(#tasks.list(repo) == 3 and core.jobs[workspace.id].exited,
    "Creating a task opens its Markdown without starting an agent")
  local input = core.input
  core.input = function() error("New tasks must open directly, without asking for a predefined title") end
  vim.cmd("TaskbayNew")
  assert(vim.wait(5000, function() return vim.bo.buftype == "acwrite" end, 10))
  local draft = vim.api.nvim_get_current_buf()
  assert(#tasks.list(repo) == 3 and vim.api.nvim_buf_get_lines(draft, 0, -1, false)[1] == "# ",
    "An empty task must not create an invalid file")
  assert(vim.wo.winbar:find(":write creates", 1, true))
  vim.cmd("silent write")
  assert(vim.bo.modified and #tasks.list(repo) == 3 and messages[#messages]:find("Keep '# Title'", 1, true),
    "A missing title must leave the draft editable and create no task")
  vim.api.nvim_buf_set_lines(draft, 0, -1, false, { "# My own task", "", "My description.", "", "- [ ] My next step" })
  vim.api.nvim_cmd({ cmd = "write", args = { temp .. "/elsewhere.md" } }, {})
  assert(not vim.uv.fs_stat(temp .. "/elsewhere.md") and #tasks.list(repo) == 3
    and messages[#messages]:find("without a filename", 1, true), "Do not silently ignore a requested destination")
  vim.cmd("silent write")
  assert(vim.wait(5000, function() return vim.b.taskbay_task and vim.b.taskbay_task.target.number == 4 end, 10),
    table.concat(messages, "\n"))
  local own = vim.b.taskbay_task.target
  assert(vim.bo.buftype == "" and not vim.bo.modified and own.task_file == "004-my-own-task.md")
  assert(tasks.get(own).body == "My description.\n\n- [ ] My next step", "Keep the user's own Markdown")
  vim.api.nvim_buf_set_lines(draft, 2, -1, false, { "A second edit." })
  vim.cmd("silent write")
  assert(#tasks.list(repo) == 4 and tasks.get(own).body == "A second edit.",
    "Later saves update the task instead of creating another one")
  ui.dashboard()
  local row
  assert(vim.wait(5000, function()
    local buffer = dash_buf()
    if not buffer or #vim.fn.win_findbuf(buffer) == 0 then return false end
    for index, line in ipairs(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)) do
      if line:find("#4 My own task", 1, true) then row = index; return true end
    end
  end, 10), "The written task must be selectable in the workspace panel: " .. table.concat(messages, "\n"))
  vim.api.nvim_win_set_cursor(vim.fn.win_findbuf(dash_buf())[1], { row, 0 })
  vim.fn.feedkeys("p", "xt")
  assert(vim.wait(10000, function()
    local active = core.current()
    local running = active and core.jobs[active.id]
    return active and active.number == own.number and active.source == "local"
      and running and running.sequence ~= nil and not running.exited
  end, 10), table.concat(messages, "\n"))
  local active = core.current()
  local running = core.jobs[active.id]
  assert(active.branch == "task/4" and vim.fn.jobwait({ running.channel }, 0)[1] == -1)
  local context
  for _, arg in ipairs(running.argv) do
    if arg:sub(1, 1) == "@" then context = table.concat(vim.fn.readfile(arg:sub(2)), "\n") end
  end
  assert(context and context:find("My own task", 1, true) and context:find("A second edit.", 1, true)
    and context:find(tasks.file(own), 1, true), "A newly written task must reach its running pi agent")
  assert(context:find("Your worktree is " .. active.path .. " (branch task/4)", 1, true)
    and context:find("create and change files only inside it", 1, true),
    "The prompt must name the worktree as the task's repository root, not the main checkout")
  assert(vim.tbl_contains(running.argv, "Implement the attached task."))
  core.stop(active)
  assert(vim.wait(4000, function() return running.exited end, 10))
  core.input = input
  -- Visual selection transfer: the exact charwise range reaches the agent's input.
  await(function() core.start(active) end)
  running = core.jobs[active.id]
  assert(vim.wait(5000, function() return running.sequence ~= nil and not running.exited end, 10),
    table.concat(messages, "\n"))
  vim.fn.writefile({ "alpha beta gamma", "delta" }, active.path .. "/notes.txt")
  vim.cmd("edit " .. vim.fn.fnameescape(active.path .. "/notes.txt"))
  local notes = vim.api.nvim_get_current_buf()
  vim.fn.setpos(".", { notes, 1, 7, 0 })
  vim.fn.feedkeys("v\27", "xt") -- the last visual mode must be charwise
  vim.fn.setpos("'<", { notes, 1, 7, 0 })
  vim.fn.setpos("'>", { notes, 1, 10, 0 })
  require("taskbay.terminal").send(true)
  local pasted
  assert(vim.wait(5000, function()
    local found = vim.fs.find("paste.txt", { path = temp, limit = 50 })[1]
    if not found then return false end
    local handle = assert(io.open(found, "rb"))
    pasted = handle:read("a")
    handle:close()
    return pasted and pasted:find("beta", 1, true) ~= nil
  end, 10), table.concat(messages, "\n") .. "\npaste: " .. tostring(pasted))
  assert(pasted:find('File: "notes.txt" 1:7-1:10 (buffer snapshot)', 1, true)
    and pasted:find("\nbeta\n```", 1, true), "The exact selection must reach pi: " .. tostring(pasted))
  assert(not pasted:find("alpha", 1, true), "A charwise selection must not transfer whole lines")
  vim.cmd.stopinsert()
  -- Panel X deletes only after confirmation: a new row loses its task file, a
  -- workspace row also its worktree and session. Long titles are clipped.
  local function panel_select(text)
    ui.dashboard()
    local index
    assert(vim.wait(5000, function()
      local buffer = dash_buf()
      if not buffer or #vim.fn.win_findbuf(buffer) == 0 then return false end
      for i, line in ipairs(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)) do
        if line:find(text, 1, true) then index = i; return true end
      end
      vim.api.nvim_set_current_win(vim.fn.win_findbuf(buffer)[1])
      vim.fn.feedkeys("]", "xt") -- the row may be on another page
    end, 50), "Panel row missing: " .. text)
    vim.api.nvim_set_current_win(vim.fn.win_findbuf(dash_buf())[1])
    vim.api.nvim_win_set_cursor(0, { index, 0 })
    return vim.api.nvim_get_current_line()
  end
  local choose = core.choose
  -- Re-opening an open panel focuses it; v / f / e act on the selected row.
  local draft = tasks.create(repo, "Draft row")
  for i = 1, 5 do tasks.create(repo, "Filler " .. i) end
  panel_select("Draft row")
  ui.dashboard()
  assert(vim.api.nvim_get_current_buf() == dash_buf(), "Re-opening focuses the open panel")
  assert(vim.wait(3000, function() return vim.api.nvim_get_current_line():find("Draft row", 1, true) ~= nil end, 10),
    "Re-opening reloads the rows and keeps the selection")
  local revealed = tasks.create(repo, "Revealed")
  ui.task_created(revealed)
  assert(vim.wait(3000, function()
    return vim.api.nvim_get_current_line():find("#" .. revealed.number .. " Revealed", 1, true) ~= nil
  end, 10), "A task written while the panel is open appears there, selected (on its page)")
  assert(vim.api.nvim_win_get_height(0) >= vim.api.nvim_buf_line_count(0) or vim.api.nvim_win_get_height(0) == vim.o.lines - 6,
    "The panel grows with its rows")
  local fields, seen = require("taskbay.fields"), nil
  local fields_open, export = fields.open, require("taskbay.remote").export_task
  fields.open = function(target) seen = target end
  panel_select("Draft row")
  vim.fn.feedkeys("f", "xt")
  assert(seen and seen.number == draft.number, "f opens a new row's fields")
  panel_select("Draft row")
  vim.fn.feedkeys("v", "xt")
  assert(vim.wait(3000, function() return (vim.b.taskbay_task or {}).target and vim.b.taskbay_task.target.number == draft.number end, 10),
    "v opens a new row's task text")
  ui.toggle_remote()
  require("taskbay.remote").export_task = function(target) seen = target end
  seen = nil
  panel_select("Draft row")
  vim.fn.feedkeys("e", "xt")
  assert(vim.wait(3000, function() return seen and seen.number == draft.number end, 10), "e exports a new row")
  seen = nil
  panel_select("#4 My own task")
  vim.fn.feedkeys("e", "xt")
  assert(vim.wait(3000, function() return seen and seen.id == active.id end, 10), "e exports a workspace row")
  ui.toggle_remote()
  fields.open, require("taskbay.remote").export_task = fields_open, export
  for _, item in ipairs(tasks.list(repo)) do
    if item.title == "Draft row" or item.title == "Revealed" or item.title:find("^Filler") then tasks.delete(item) end
  end
  -- :TaskbayReload reloads the draft's issue; :TaskbaySetup reports a successful install.
  local editor = require("taskbay.editor")
  local editor_open, reloaded = editor.open, nil
  editor.open = function(target, reload) reloaded = { target = target, reload = reload } end
  vim.b.taskbay_task = { target = { number = 5 } }
  vim.cmd("TaskbayReload")
  editor.open, vim.b.taskbay_task = editor_open, nil
  assert(reloaded.reload and reloaded.target.number == 5, ":TaskbayReload reloads the draft's issue")
  local executable, run = vim.fn.executable, core.run
  vim.fn.executable = function(name) return name == "npm" and 1 or executable(name) end
  core.run = function() return { stdout = "added 1 package" } end
  vim.cmd("TaskbaySetup")
  assert(vim.wait(3000, function() return messages[#messages]:find("Pinned pi-subagents installed", 1, true) ~= nil end, 10))
  vim.fn.executable, core.run = executable, run
  -- A new row already shows its checklist progress.
  local checklist = tasks.create(repo, "Checklist row", "- [x] a\n- [ ] b")
  assert(panel_select("Checklist row"):find("Checklist row  1/2", 1, true), "New rows show checklist progress")
  vim.cmd.close()
  tasks.delete(checklist)
  local long = tasks.file(tasks.create(repo, "Long " .. ("x"):rep(200)))
  local own_file = tasks.file(own)
  assert(panel_select("Long xxx"):find("x...", 1, true), "Long titles are clipped with an ellipsis")
  core.choose = function() return "Cancel" end
  vim.fn.feedkeys("X", "xt")
  assert(vim.wait(2000, function() return #vim.fn.win_findbuf(dash_buf() or -1) == 0 end, 10))
  assert(vim.uv.fs_stat(long), "Cancel keeps the task")
  panel_select("Long xxx")
  core.choose = function() return "Delete local task file" end
  vim.fn.feedkeys("X", "xt")
  assert(vim.wait(3000, function() return not vim.uv.fs_stat(long) end, 10), "X deletes a new task's file")
  panel_select("#4 My own task")
  core.choose = function() return "Delete task, worktree and session" end
  vim.fn.feedkeys("X", "xt")
  assert(vim.wait(8000, function()
    return not core.workspaces[active.id] and not vim.uv.fs_stat(active.path) and not vim.uv.fs_stat(own_file)
  end, 10), "X deletes a workspace with its worktree and task file: " .. table.concat(messages, "\n"))
  core.choose = choose
  local fresh = temp .. "/fresh"
  vim.fn.mkdir(fresh, "p")
  await(function() core.git(fresh, "init", "-b", "main") end)
  local fresh_repo = await(function() return core.repository(fresh) end)
  local fresh_task = tasks.create(fresh_repo, "Plan the demo")
  ui.launch(fresh_repo, fresh_task)
  assert(vim.wait(5000, function()
    return messages[#messages]:find("no commits yet", 1, true) ~= nil
  end, 10), "A repository without commits must explain how to start: " .. messages[#messages])
  assert(not vim.uv.fs_stat(temp .. "/fresh-worktrees"), "No worktree is created without a base commit")
  local count = #messages
  vim.cmd("TaskbayImport")
  assert(#messages > count and messages[#messages]:find("GitHub integration is disabled", 1, true))
end, debug.traceback)

for id, job in pairs(core.jobs) do
  if not job.exited then core.stop(core.workspaces[id]) end
end
vim.wait(4000, function()
  for _, job in pairs(core.jobs) do if not job.exited then return false end end
  return true
end, 10)
vim.fn.delete(temp, "rf")
if not ok then
  io.stderr:write(tostring(failure) .. "\n")
  vim.cmd("cquit 1")
end
print("taskbay tasks: offline providers, safe files, editing, new-task launch and session resume passed")
vim.cmd("qa!")
