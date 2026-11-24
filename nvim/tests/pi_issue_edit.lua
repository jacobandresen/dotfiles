-- Run: timeout 30 nvim --headless -u NONE -i NONE -l nvim/tests/pi_issue_edit.lua
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
local core = require("util.pi_issues")
local editor = require("util.pi_issue_edit")
local temp = vim.fn.tempname()
vim.fn.mkdir(temp, "p")
vim.g.pi_issues = { state_dir = temp .. "/state", github_enabled = true }
local messages, edits = {}, {}
vim.notify = function(message) messages[#messages + 1] = tostring(message) end
local target = { id = "test", host = "github.com", repo = "test/repo", number = 42, path = temp }
local other = vim.tbl_extend("force", target, { id = "other", number = 43 })
core.workspaces[target.id], core.workspaces[other.id] = target, other
vim.t.pi_issue = target.id
local remote = { title = "Original issue", body = "Original body", url = "https://github.com/test/repo/issues/42",
  labels = { { name = "bug" }, { name = "cli" } }, state = "open", milestone = { title = "v1" },
  comments = { { author = { login = "jacob" }, body = "Original comment" } } }
local choice, request = "Cancel", "Clarify the acceptance criteria."
local run = core.run
local on_fetch
core.run = function(argv, cwd, optional, stdin)
  assert(argv[1] == "gh" and cwd == temp, "Use the selected repository's working directory")
  assert(argv[4] == "42" and argv[6] == "github.com/test/repo", "Keep the explicit issue identity")
  if argv[3] == "view" then
    if on_fetch then on_fetch() end
    return { code = 0, stdout = vim.json.encode(remote) }
  end
  assert(argv[3] == "edit", vim.inspect(argv))
  assert(argv[7] == "--title" and argv[9] == "--body-file" and argv[10] == "-")
  edits[#edits + 1] = { argv = argv, body = stdin }
  remote.title, remote.body = argv[8], stdin
  return { code = 0, stdout = "updated" }
end
core.choose = function() return choice end
core.input = function() return request end
local function lines(buf) return vim.api.nvim_buf_get_lines(buf, 0, -1, false) end
local function expect_message(fn, pattern)
  local count = #messages
  fn()
  assert(#messages > count and messages[#messages]:find(pattern, 1, true), table.concat(messages, "\n"))
end

local ok, failure = pcall(function()
  editor.open()
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  assert(vim.b[buf].pi_issue_draft.target.number == 42)
  assert(lines(buf)[1] == "# Original issue" and lines(buf)[3] == "Original body")
  assert(#edits == 0 and not next(core.jobs), "Viewing an issue must not publish or start agents")
  local body = 'Acceptance criteria:\n"quotes" and --flags stay literal.'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# Revised issue", "", 'Acceptance criteria:', '"quotes" and --flags stay literal.' })
  editor.publish(buf)
  assert(#edits == 0 and not vim.bo[buf].modified, "Cancelling publication saves only the local draft")
  editor.open(target)
  assert(vim.api.nvim_get_current_buf() == buf and lines(buf)[1] == "# Revised issue",
    "Reopening must retain the existing draft")
  choice = "Publish title and body"
  editor.publish(buf)
  assert(#edits == 1 and edits[1].body == body, "Publish the Markdown body through stdin")
  assert(remote.title == "Revised issue" and target.title == "Revised issue")
  assert(other.title == nil, "Publishing one issue must not retitle another")
  assert(vim.b[buf].pi_issue_draft.body == body, "Advance the conflict baseline after publishing")
  local baseline = vim.json.decode(table.concat(
    vim.fn.readfile(temp .. "/state/issue-drafts/" .. vim.fn.sha256("github.com/test/repo#42")
      .. "/baseline.json"), "\n"))
  assert(baseline.issue and baseline.issue.labels[1].name == "bug" and baseline.issue.comments[1].body
    == "Original comment" and baseline.issue.milestone.title == "v1",
    "Publishing must keep the full original issue snapshot in the local draft")

  remote.body = "Someone else's edit"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# Local changes", "", "Keep my draft" })
  expect_message(function() editor.publish(buf) end, "Issue changed on GitHub")
  assert(#edits == 1 and lines(buf)[1] == "# Local changes", "Never overwrite concurrent GitHub changes")
  choice = "Cancel"
  editor.open(target, true)
  assert(lines(buf)[1] == "# Local changes", "Cancelling reload preserves the draft")
  choice = "Replace local draft"
  editor.open(target, true)
  assert(lines(buf)[3] == "Someone else's edit" and not vim.bo[buf].modified)

  choice = "Publish title and body"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Missing title heading", "", "Body" })
  expect_message(function() editor.publish(buf) end, "Keep '# Title'")
  assert(#edits == 1)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# Revised again", "", "Body" })
  on_fetch = function() vim.api.nvim_buf_set_lines(buf, 2, -1, false, { "Changed during confirmation" }) end
  expect_message(function() editor.publish(buf) end, "Draft changed during confirmation")
  assert(#edits == 1, "Concurrent local edits must not be published without review")
  on_fetch = function() error("GitHub unavailable") end
  expect_message(function() editor.publish(buf) end, "GitHub unavailable")
  on_fetch = nil
  vim.api.nvim_buf_set_lines(buf, 2, -1, false, { "Before formatting" })
  vim.api.nvim_create_autocmd("BufWritePre", {
    buffer = buf,
    once = true,
    callback = function() vim.api.nvim_buf_set_lines(buf, 2, -1, false, { "Formatted on save" }) end,
  })
  editor.publish(buf)
  assert(#edits == 2, "A failed publication must release its in-flight guard")
  assert(edits[2].body == "Formatted on save", "Publish the saved content, including format-on-save changes")

  core.jobs[target.id] = { channel = 123, exited = false }
  local shown, sent
  core.show = function(workspace) shown = workspace end
  local send = vim.api.nvim_chan_send
  vim.api.nvim_chan_send = function(channel, text)
    assert(channel == 123)
    sent = text
  end
  vim.t.pi_issue = other.id
  expect_message(function() editor.agent(buf) end, "Switch to this task's workspace")
  assert(not sent, "Never send an issue draft to another issue's agent")
  vim.t.pi_issue = target.id
  request = nil
  editor.agent(buf)
  assert(not sent, "Cancelled revision instructions must not reach pi")
  request = "Clarify acceptance criteria."
  vim.api.nvim_buf_set_lines(buf, 2, -1, false, { "Unsaved draft body" })
  editor.agent(buf)
  assert(shown == target and sent:find(vim.json.encode(path), 1, true))
  assert(sent:find("Do not publish to GitHub", 1, true) and sent:find(request, 1, true))
  assert(not vim.bo[buf].modified and vim.fn.readfile(path)[3] == "Unsaved draft body",
    "Save local edits before asking pi to revise them")
  local count = #edits
  assert(count == 2, "Requesting agent revisions must not edit the live issue")
  core.jobs[target.id].exited = true
  expect_message(function() editor.agent(buf) end, "Start this task's pi")
  vim.api.nvim_chan_send = send

  core.run = run
  local output
  core.task(function()
    output = core.run({ "python3", "-c", "import sys; print(sys.stdin.read())" }, temp, false, body)
  end)
  assert(vim.wait(5000, function() return output ~= nil end, 10))
  assert(vim.trim(output.stdout) == body, "The command runner must pass stdin without shell expansion")
end)

vim.fn.delete(temp, "rf")
if not ok then
  io.stderr:write(tostring(failure) .. "\n")
  vim.cmd("cquit 1")
end
print("pi issue drafts: local edits, confirmed publication, conflicts, reload and agent routing passed")
vim.cmd("qa!")
