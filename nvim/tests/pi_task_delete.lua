-- Run: timeout 60 nvim --headless -u NONE -i NONE -l nvim/tests/pi_task_delete.lua
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
local core = require("util.pi_issues")
local tasks = require("util.pi_tasks")
local temp = vim.fn.tempname()
local repo_path = temp .. "/repo"
vim.fn.mkdir(repo_path, "p")
vim.g.pi_issues = { state_dir = temp .. "/state" }
_G.LazyVim = { root = function() return repo_path end }

local function await(fn)
  local done, result, failure = false
  core.task(function()
    local ok, value = pcall(fn)
    if ok then result = value else failure = value end
    done = true
  end)
  assert(vim.wait(15000, function() return done end, 10), "Timed out")
  assert(not failure, failure)
  return result
end

local function git(...)
  local args = { ... }
  return vim.trim(await(function() return core.git(repo_path, unpack(args)) end))
end

local ok, failure = xpcall(function()
  git("init", "-b", "main")
  git("config", "user.name", "Test")
  git("config", "user.email", "test@example.invalid")
  core.write(repo_path .. "/README", "test\n")
  git("add", "README")
  git("commit", "-m", "Initial")
  local repo = await(function() return core.repository(repo_path) end)

  local pending = tasks.create(repo, "Pending deletion")
  local pending_path = tasks.file(pending)
  tasks.delete(pending)
  assert(not vim.uv.fs_stat(pending_path))

  local prepared = tasks.create(repo, "Prepared deletion")
  local workspace = await(function() return core.prepare(repo, prepared, "HEAD", true) end)
  local task_path, worktree_path, state_path = tasks.file(prepared), workspace.path, core.directory(workspace)
  await(function() return core.delete(workspace) end)
  assert(not vim.uv.fs_stat(task_path), "Task file was not deleted")
  assert(not vim.uv.fs_stat(worktree_path), "Worktree was not deleted")
  assert(not vim.uv.fs_stat(state_path), "Workspace state was not deleted")
  assert(core.workspaces[workspace.id] == nil and core.jobs[workspace.id] == nil)
  assert(#tasks.list(repo) == 0)
  local worktrees = await(function() return core.worktrees(repo.root) end)
  for _, entry in ipairs(worktrees) do assert(entry.path ~= worktree_path) end

  -- A workspace whose worktree and task file were already removed externally
  -- (stale dashboard row) must still delete cleanly.
  tasks.delete(tasks.create(repo, "Stale deletion"))
  local stale = tasks.create(repo, "Stale deletion 2")
  local stale_workspace = await(function() return core.prepare(repo, stale, "HEAD", true) end)
  vim.fn.delete(stale_workspace.path, "rf") -- remove without git worktree remove
  vim.uv.fs_unlink(tasks.file(stale_workspace))
  await(function() return core.delete(stale_workspace) end)
  assert(core.workspaces[stale_workspace.id] == nil)
  assert(not vim.uv.fs_stat(core.directory(stale_workspace)), "Stale workspace state was not deleted")
  local worktrees = await(function() return core.worktrees(repo.root) end)
  for _, entry in ipairs(worktrees) do assert(entry.path ~= stale_workspace.path) end

  -- tasks.delete tolerates an already-missing task file.
  local gone = tasks.create(repo, "Already gone")
  vim.uv.fs_unlink(tasks.file(gone))
  await(function() return tasks.delete(gone) end)
end, debug.traceback)

vim.fn.delete(temp, "rf")
if not ok then
  io.stderr:write(tostring(failure) .. "\n")
  vim.cmd("cquit 1")
end
print("pi task deletion: pending files, prepared worktrees and persisted sessions passed")
vim.cmd("qa!")
