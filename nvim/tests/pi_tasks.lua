-- Run: timeout 60 nvim --headless -u NONE -i NONE -l nvim/tests/pi_tasks.lua
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
local core = require("util.pi_issues")
local tasks = require("util.pi_tasks")
local editor = require("util.pi_issue_edit")
local temp = vim.fn.tempname()
vim.fn.mkdir(temp .. "/repo", "p")
vim.g.pi_issues = { state_dir = temp .. "/state", pi = vim.fn.getcwd() .. "/nvim/tests/fixtures/pi_stub.py" }
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
  }) do expect_error(fn, "GitHub integration is disabled") end
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
  vim.g.pi_issues = vim.tbl_extend("force", vim.g.pi_issues, { github_enabled = true })
  local github_workspace = await(function()
    return core.prepare(github, { number = 1, title = "GitHub issue" }, "HEAD", true)
  end)
  vim.g.pi_issues = vim.tbl_extend("force", vim.g.pi_issues, { github_enabled = false })
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
  local restored = dofile(vim.fs.dirname(core.path()) .. "/lua/util/pi_issues.lua")
  restored.load()
  assert(restored.workspaces[workspace.id].task_file == a.task_file)
  assert(tasks.get(restored.workspaces[workspace.id]).title == "External checkpoint")
  assert(next(restored.jobs) == nil, "Restoring local task metadata must not start agents")

  vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/snacks.nvim")
  _G.Snacks = require("snacks")
  Snacks.setup({ picker = { enabled = true }, notifier = { enabled = false } })
  local ui = require("util.pi_issues_ui")
  ui.setup()
  ui.tasks()
  assert(vim.wait(5000, function()
    local picker = Snacks.picker.get()[1]
    return picker and picker:count() == 2
  end, 10), table.concat(messages, "\n"))
  local picker = Snacks.picker.get()[1]
  assert(picker.opts.title == "repo / Local Tasks")
  picker.opts.actions.view_issue(picker)
  assert(vim.wait(3000, function()
    return vim.b.pi_issue_draft and vim.b.pi_issue_draft.target.source == "local"
  end, 10))
  vim.cmd("PiTaskNew Review the remaining tests")
  assert(vim.wait(5000, function()
    return vim.b.pi_issue_draft and vim.b.pi_issue_draft.target.number == 3
  end, 10), table.concat(messages, "\n"))
  assert(#tasks.list(repo) == 3 and core.jobs[workspace.id].exited,
    "Creating a task opens its Markdown without starting an agent")
  local input = core.input
  core.input = function() error("New tasks must open directly, without asking for a predefined title") end
  vim.cmd("PiTaskNew")
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
  assert(vim.wait(5000, function() return vim.b.pi_issue_draft and vim.b.pi_issue_draft.target.number == 4 end, 10),
    table.concat(messages, "\n"))
  local own = vim.b.pi_issue_draft.target
  assert(vim.bo.buftype == "" and not vim.bo.modified and own.task_file == "004-my-own-task.md")
  assert(tasks.get(own).body == "My description.\n\n- [ ] My next step", "Keep the user's own Markdown")
  vim.api.nvim_buf_set_lines(draft, 2, -1, false, { "A second edit." })
  vim.cmd("silent write")
  assert(#tasks.list(repo) == 4 and tasks.get(own).body == "A second edit.",
    "Later saves update the task instead of creating another one")
  core.input = function(prompt, default)
    assert(prompt:find("Base ref", 1, true) and default == "HEAD")
    return default
  end
  ui.tasks("local", "My own task", 50, repo)
  assert(vim.wait(5000, function()
    local selected = Snacks.picker.get()[1]
    return selected and selected:count() == 1
  end, 10), table.concat(messages, "\n"))
  picker = Snacks.picker.get()[1]
  picker.opts.actions.review_launch(picker)
  assert(vim.wait(5000, function()
    return vim.inspect(vim.api.nvim_win_get_config(0).title):find("Review Task Launch", 1, true)
  end, 10), table.concat(messages, "\n"))
  local start
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
    if mapping.lhs == "s" then start = mapping.callback end
  end
  assert(start, "The launch review must offer starting pi")
  start()
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
  local fresh = temp .. "/fresh"
  vim.fn.mkdir(fresh, "p")
  await(function() core.git(fresh, "init", "-b", "main") end)
  local fresh_repo = await(function() return core.repository(fresh) end)
  local fresh_task = tasks.create(fresh_repo, "Plan the demo")
  ui.launch(fresh_repo, { fresh_task })
  assert(vim.wait(5000, function()
    return messages[#messages]:find("no commits yet", 1, true) ~= nil
  end, 10), "A repository without commits must explain how to start: " .. messages[#messages])
  assert(not vim.uv.fs_stat(temp .. "/fresh-worktrees"), "No worktree is created without a base commit")
  local count = #messages
  vim.cmd("PiTasks github")
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
print("pi tasks: offline providers, safe files, editing, new-task launch and session resume passed")
vim.cmd("qa!")
