-- Run: timeout 30 nvim --headless -u NONE -i NONE -l nvim/tests/pi_task_copy.lua
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
local core = require("util.pi_issues")
local tasks = require("util.pi_tasks")
local ui = require("util.pi_issues_ui")
local temp = vim.fn.tempname()
vim.fn.mkdir(temp .. "/repo", "p")
vim.g.pi_issues = { state_dir = temp .. "/state" }
_G.LazyVim = { root = setmetatable({}, { __call = function() return temp .. "/repo" end }) }
local messages, gh_calls, creations = {}, {}, {}
vim.notify = function(message) messages[#messages + 1] = tostring(message) end
local choice = "Cancel"
local on_confirm, fail_create, create_url
core.choose = function()
  if on_confirm then on_confirm() end
  return choice
end
local remote = { title = 'Remote "task"', body = "## Description\n\n- [ ] First step\n- [x] Existing progress",
  url = "https://github.com/test/repo/issues/42" }
local original_run = core.run
core.run = function(argv, cwd, optional, stdin)
  if argv[1] ~= "gh" then return original_run(argv, cwd, optional, stdin) end
  assert(core.settings().github_enabled, "Disabled integration must not invoke gh")
  gh_calls[#gh_calls + 1] = argv
  if argv[2] == "repo" then
    return { code = 0, stdout = vim.json.encode({
      nameWithOwner = "test/repo", url = "https://github.com/test/repo", defaultBranchRef = { name = "main" },
    }) }
  end
  if argv[3] == "view" then return { code = 0, stdout = vim.json.encode(remote) } end
  assert(argv[3] == "create" and argv[4] == "--repo" and argv[5] == "github.com/test/repo")
  assert(argv[6] == "--title" and argv[8] == "--body-file" and argv[9] == "-")
  if fail_create then error("GitHub creation failed") end
  creations[#creations + 1] = { title = argv[7], body = stdin }
  return { code = 0, stdout = create_url or ("https://github.com/test/repo/issues/" .. (98 + #creations) .. "\n") }
end
local function await(fn)
  local result, done, failure
  core.task(function()
    local ok, value = pcall(fn)
    if ok then result = value else failure = value end
    done = true
  end)
  assert(vim.wait(5000, function() return done end, 10), table.concat(messages, "\n"))
  assert(not failure, failure)
  return result
end
local function action(fn)
  local thread = fn()
  assert(vim.wait(5000, function() return coroutine.status(thread) == "dead" end, 10), table.concat(messages, "\n"))
end
local function enabled(value)
  vim.g.pi_issues = vim.tbl_extend("force", vim.g.pi_issues, { github_enabled = value })
end

local ok, failure = pcall(function()
  for _, args in ipairs({
    { "init", "-b", "main" }, { "config", "user.name", "Test" },
    { "config", "user.email", "test@example.invalid" },
  }) do await(function() core.git(temp .. "/repo", unpack(args)) end) end
  core.write(temp .. "/repo/code.txt", "Original\n")
  await(function() core.git(temp .. "/repo", "add", "code.txt") end)
  await(function() core.git(temp .. "/repo", "commit", "-m", "Initial") end)
  local repo = await(function() return core.repository(temp .. "/repo") end)
  action(function() return ui.import_task("42") end)
  assert(#gh_calls == 0 and messages[#messages]:find("disabled", 1, true))
  enabled(true)
  action(function() return ui.import_task("42") end)
  assert(#tasks.list(repo) == 0 and #creations == 0, "Cancelling import must not create a task")
  choice = "Import as local task"
  action(function() return ui.import_task("42") end)
  local imported = vim.b.pi_issue_draft.target
  assert(imported.source == "local" and imported.number == 1)
  local copied = tasks.get(imported)
  assert(copied.title == remote.title and copied.body == remote.body, "Import must preserve title and Markdown")
  assert(next(core.workspaces) == nil and next(core.jobs) == nil, "Import must not move or start workspaces")
  assert(#creations == 0, "Import must not create or modify GitHub issues")
  local buf = vim.api.nvim_get_current_buf()
  local path = tasks.file(imported)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# Local revision", "", "Updated acceptance criteria." })
  enabled(false)
  local calls = #gh_calls
  action(ui.export_task)
  assert(#gh_calls == calls and #creations == 0 and messages[#messages]:find("disabled", 1, true))
  enabled(true)
  choice = "Cancel"
  action(ui.export_task)
  assert(#creations == 0 and tasks.get(imported).title == "Local revision",
    "Cancelled export may save locally but must not publish")
  choice = "Create GitHub issue"
  on_confirm = function() vim.api.nvim_buf_set_lines(buf, 2, -1, false, { "Changed while confirming" }) end
  action(ui.export_task)
  assert(#creations == 0 and messages[#messages]:find("changed during confirmation", 1, true))
  on_confirm = nil
  fail_create = true
  action(ui.export_task)
  assert(#creations == 0 and messages[#messages]:find("GitHub creation failed", 1, true))
  fail_create = false
  action(ui.export_task)
  assert(#creations == 1 and creations[1].title == "Local revision"
    and creations[1].body == "Changed while confirming", "Export must publish saved title/body via stdin")
  assert(vim.uv.fs_stat(tasks.file(imported)) and tasks.get(imported).title == "Local revision")
  assert(vim.b.pi_issue_draft.target.source == "local" and next(core.jobs) == nil,
    "Export must not switch task identity or launch an agent")
  assert(remote.title == 'Remote "task"' and remote.body:find("Existing progress", 1, true),
    "Copying must not alter the source GitHub issue")
  on_confirm = function()
    on_confirm = nil
    action(ui.export_task)
    assert(messages[#messages]:find("already in progress", 1, true))
  end
  action(ui.export_task)
  assert(#creations == 2, "Concurrent export requests must not create duplicate issues")
  for _, url in ipairs({
    "https://github.com/other/repo/issues/42", "https://other.example/test/repo/issues/42",
    "https://github.com/test/repo/issues/9007199254740992",
  }) do
    create_url = url
    action(ui.export_task)
    assert(messages[#messages]:find("Unexpected issue URL; inspect GitHub before retrying", 1, true),
      "Do not report success for an unexpected issue destination or ID")
  end
  create_url = nil
  vim.t.pi_issue = "active-github"
  core.workspaces["active-github"] = {
    source = "github", host = "github.com", repo = "test/repo", number = 42, path = repo.root,
  }
  choice = "Import as local task"
  action(function() return ui.import_task() end)
  assert(vim.b.pi_issue_draft.target.number == 2 and #tasks.list(repo) == 2,
    "Import without an argument uses the active GitHub issue")
end)

vim.fn.delete(temp, "rf")
if not ok then
  io.stderr:write(tostring(failure) .. "\n")
  vim.cmd("cquit 1")
end
print("pi task copies: disabled integration, confirmed import/export, preserved Markdown and originals passed")
vim.cmd("qa!")
