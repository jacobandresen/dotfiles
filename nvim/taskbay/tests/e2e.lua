-- End-to-end: write tasks, pick three, run three pi agents at once, using the real
-- LazyVim config and real keystrokes. pi is replaced by a scripted, offline stand-in.
-- Run: timeout 180 nvim --headless -u NONE -i NONE -l tests/e2e.lua
local uv = vim.uv
local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/harness.lua")()
local repo, release, sh, lua, keys, wait_for, pick, step, agents, boot =
  H.repo, H.release, H.sh, H.lua, H.keys, H.wait_for, H.pick, H.step, H.agents, H.boot

local tasks = {
  { title = "Add a farewell function", body = "Add farewell() next to greet() in app.py." },
  { title = "Document the greeting API", body = "Describe greet() in README.md." },
  { title = "Add greeting tests", body = "Cover greet() with a unit test." },
  { title = "Fourth queued task", body = "Waits for a free agent slot. [no changes]" },
}

H.run("taskbay e2e: wrote 4 tasks, ran 3 agents at once, queued a 4th, sent context, revised, stopped, resumed, finished and merged, quit and restored", function()
  boot()

  step("an error prompt is reported instead of hanging the harness")
  keys(":lua error('e2e-prompt')<CR>")
  assert(vim.wait(30000, function() return H.rpc("nvim_get_mode").blocking end, 50), "The error must raise a prompt")
  -- Only the deferred request gets a short timeout; the slow traced editor needs longer for the rest.
  local rpc_timeout = H.opts.rpc_timeout
  H.opts.rpc_timeout = 1000
  local ok, err = pcall(lua, "return 1")
  H.opts.rpc_timeout = rpc_timeout
  assert(not ok and err:find("blocked at a prompt", 1, true) and err:find("e2e-prompt", 1, true), err)
  assert(lua("return 2") == 2, "The editor answers again once the prompt is dismissed")

  step("write three tasks with Space a n")
  for index = 1, 3 do
    local task = tasks[index]
    keys("<Esc><Space>an")
    wait_for("Space a n must open a blank task ready for typing", [[
      return vim.bo.buftype == "acwrite" and vim.fn.mode() == "i"
        and vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "# "
    ]])
    keys(task.title .. "<CR><CR>" .. task.body .. "<Esc>:write<CR>")
    wait_for("Writing task " .. index .. " must create it", [[
      local info = vim.b.taskbay_task
      return info ~= nil and info.target.number == ... and vim.bo.buftype == "" and not vim.bo.modified
    ]], 8000, index)
  end
  step("write a fourth task with :TaskbayNew")
  keys("<Esc>:TaskbayNew " .. tasks[4].title .. "<CR>")
  wait_for(":TaskbayNew <title> must create and open task 4",
    "return vim.b.taskbay_task ~= nil and vim.b.taskbay_task.target.number == 4")
  keys("Go<CR>" .. tasks[4].body .. "<Esc>:write<CR>")
  wait_for("Saving task 4 must keep the body", "return not vim.bo.modified")
  local files = vim.fn.readdir(repo .. "/.tasks")
  table.sort(files)
  assert(#files == 4, vim.inspect(files))
  for index, task in ipairs(tasks) do
    local content = table.concat(vim.fn.readfile(repo .. "/.tasks/" .. files[index]), "\n")
    assert(files[index]:match("^00" .. index .. "%-"), files[index])
    assert(content:find("# " .. task.title, 1, true) == 1, content)
    assert(content:find(task.body, 1, true), "Typed body must be saved: " .. content)
  end
  assert(#agents() == 0, "Writing tasks must not start pi")
  keys("<Esc><Space>aw")
  wait_for("Written tasks appear in Space a w before they start", [[
    local lines = e2e.float_lines("Task Workspaces") or {}
    local text = table.concat(lines, "\n")
    if not text:find("0 of 3 agents running  ·  4 tasks", 1, true) then return false end
    for number = 1, 4 do
      local row = e2e.dashboard_row(number)
      if not row or not lines[row]:find(" new ", 1, true) then return false end
    end
    return true
  ]])
  keys("x")
  wait_for("Actions that need a running agent explain instead",
    "return _G.e2e_messages[#_G.e2e_messages]:find('Not started yet', 1, true) ~= nil")
  keys("q")

  step("start three tasks from the workspace panel")
  for number = 1, 3 do
    keys("<C-\\><C-n><Esc><Space>aw")
    wait_for("Workspace panel must list task " .. number, "return e2e.dashboard_row(" .. number .. ") ~= nil")
    lua("vim.api.nvim_win_set_cursor(0, { e2e.dashboard_row(" .. number .. "), 0 })")
    keys("p")
    wait_for("Task " .. number .. " must start from the workspace panel", [[
      local job = e2e.job(...)
      return job ~= nil and not job.exited and job.activity == "working"
    ]], 15000, number)
  end
  wait_for("Three pi agents must be working at the same time", [[
    for number = 1, 3 do
      local job = e2e.job(number)
      if not job or job.exited or job.activity ~= "working" then return false end
    end
    return e2e.live() == 3
  ]], 15000)
  lua([[assert(not e2e.prompt_open(), "Starting from the panel shows no prompts")]])

  step("check isolation of the three running agents")
  local started = {}
  for _, event in ipairs(agents()) do
    if event.event == "started" then started[#started + 1] = event end
  end
  assert(#started == 3, vim.inspect(started))
  local seen_cwd, seen_pid = {}, {}
  for _, event in ipairs(started) do
    local number = tonumber(event.cwd:match("task%-(%d+)$"))
    assert(number and tasks[number], "Agent must run in a task worktree: " .. event.cwd)
    assert(not seen_cwd[event.cwd] and not seen_pid[event.pid], "Each task needs its own process and worktree")
    seen_cwd[event.cwd], seen_pid[event.pid] = true, true
    assert(event.prompt:find(tasks[number].title, 1, true) and event.prompt:find(tasks[number].body, 1, true),
      "Agent " .. number .. " must receive its own task")
    assert(event.prompt:find(repo .. "/.tasks/00" .. number .. "-", 1, true), "Prompt names the task file")
    for other, task in ipairs(tasks) do
      if other ~= number then assert(not event.prompt:find(task.title, 1, true), "Task context leaked") end
    end
    assert(vim.tbl_contains(event.args, "Implement the attached task."), "The task is submitted on start")
    assert(not vim.tbl_contains(event.args, "--model"), "New tasks use pi-agent's default model")
    assert(sh({ "git", "branch", "--show-current" }, event.cwd) == "task/" .. number)
  end
  lua([[
    local core = require("taskbay.core")
    local tabs = vim.api.nvim_list_tabpages()
    assert(#tabs == 4, "One code tab per task plus the original: " .. #tabs)
    local owned = {}
    for _, tab in ipairs(tabs) do
      local id = vim.t[tab].taskbay_workspace
      if id then
        owned[core.workspaces[id].number] = true
        local terminal = false
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
          terminal = terminal or vim.api.nvim_win_get_buf(win) == core.jobs[id].buf
        end
        assert(terminal, "Each task tab shows its own pi terminal")
      end
    end
    assert(owned[1] and owned[2] and owned[3] and not owned[4])
    local tabline = vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true }).str
    for number = 1, 3 do
      assert(tabline:find("project/" .. number .. "-", 1, true) and tabline:find(" working", 1, true), tabline)
    end
  ]])
  assert(sh({ "git", "status", "--porcelain" }) == "?? .tasks/", "The main checkout must stay untouched")

  step("dashboard shows three live agents")
  keys("<C-\\><C-n><Space>aw")
  wait_for("Space a w must open the dashboard", "return e2e.float_lines('Task Workspaces') ~= nil")
  lua([[
    local text = table.concat(e2e.float_lines("Task Workspaces"), "\n")
    assert(text:find("3 of 3 agents running", 1, true), text)
    for number = 1, 3 do
      assert(e2e.float_lines("Task Workspaces")[e2e.dashboard_row(number)]:find("working", 1, true), text)
    end
  ]])
  keys("q")

  step("Enter and dashboard digits jump to a running task's pi")
  keys("<Esc><Space>aw")
  wait_for("Workspace panel lists task 3", "return e2e.dashboard_row(3) ~= nil")
  lua("vim.api.nvim_win_set_cursor(0, { e2e.dashboard_row(3), 0 })")
  wait_for("The footer follows the selected running task", [[
    local _, win = e2e.float_lines("Task Workspaces")
    return vim.inspect(vim.api.nvim_win_get_config(win).footer):find("x stop", 1, true) ~= nil
  ]])
  keys("<CR>")
  wait_for("Enter jumps into task 3's pi terminal", [[
    local core = require("taskbay.core")
    return core.current() == e2e.by_number(3) and vim.api.nvim_get_current_buf() == e2e.job(3).buf
  ]])
  keys("<C-\\><C-n><Space>aw")
  wait_for("Dashboard numbers its rows", [[
    local lines, win = e2e.float_lines("Task Workspaces")
    local row = e2e.dashboard_row(2)
    return row ~= nil and lines[row]:match("^ 2 ") ~= nil and win == vim.api.nvim_get_current_win()
  ]])
  keys("2")
  wait_for("2 jumps into task 2's pi terminal", [[
    local core = require("taskbay.core")
    return core.current() == e2e.by_number(2) and vim.api.nvim_get_current_buf() == e2e.job(2).buf
      and not e2e.float_lines("Task Workspaces")
  ]])
  keys("<C-\\><C-n>")

  step("a fourth task is prepared but must wait for a slot")
  keys("<C-\\><C-n><Esc><Space>aw")
  wait_for("Workspace panel must list task 4", "return e2e.dashboard_row(4) ~= nil")
  lua("vim.api.nvim_win_set_cursor(0, { e2e.dashboard_row(4), 0 })")
  keys("p")
  wait_for("The fourth task must be prepared without starting",
    "return table.concat(_G.e2e_messages, '\\n'):find('when a slot is free', 1, true) ~= nil")
  lua([[
    local core = require("taskbay.core")
    assert(e2e.live() == 3 and not e2e.job(4), "Never exceed three live agents")
    assert(core.status(e2e.by_number(4)) == "prepared")
    assert(core.current() == e2e.by_number(4), "The prepared task opens its own tab")
  ]])
  keys("<Esc><Space>ap")
  wait_for("Space a p must refuse a fourth agent",
    "return _G.e2e_messages[#_G.e2e_messages]:find('Agent limit reached', 1, true) ~= nil")
  assert(#agents() == 3, "No fourth process may start")

  step("agents finish their work independently")
  vim.fn.writefile({}, release)
  wait_for("All three agents must settle", [[
    for number = 1, 3 do
      local job = e2e.job(number)
      if job.activity ~= "idle" or job.outcome ~= "success" then return false end
    end
    return true
  ]], 10000)
  for number = 1, 3 do
    local result = table.concat(vim.fn.readfile(repo .. "-worktrees/task-" .. number .. "/AGENT_RESULT.md"), "\n")
    assert(result:find(tasks[number].title, 1, true), result)
  end
  assert(not uv.fs_stat(repo .. "/AGENT_RESULT.md"), "Agents must not write to the main checkout")
  wait_for("Settled agents refresh their file counts", [[
    for number = 1, 3 do
      if e2e.by_number(number).files ~= 1 then return false end
    end
    return true
  ]])
  lua([[
    local core = require("taskbay.core")
    for number = 1, 3 do
      assert(core.status(e2e.by_number(number)) == "idle")
      assert(core.jobs[e2e.by_number(number).id].model == "e2e/scripted-agent")
    end
  ]])

  step("Space a s sends context to the agent of the current tab only")
  lua([[
    local core = require("taskbay.core")
    core.open(e2e.by_number(2))
    vim.cmd.edit(e2e.by_number(2).path .. "/app.py")
    vim.api.nvim_buf_set_lines(0, -1, -1, false, { "# context for task two" })
  ]])
  keys("<Esc><Space>as")
  wait_for("Context must reach agent 2", [[
    local path = require("taskbay.core").directory(e2e.by_number(2)) .. "/paste.txt"
    return vim.uv.fs_stat(path) ~= nil and table.concat(vim.fn.readfile(path), "\n"):find("context for task two", 1, true) ~= nil
  ]])
  lua([[
    local core = require("taskbay.core")
    for _, number in ipairs({ 1, 3 }) do
      assert(not vim.uv.fs_stat(core.directory(e2e.by_number(number)) .. "/paste.txt"), "Context leaked to " .. number)
    end
  ]])
  keys("<C-\\><C-n>")

  step("Space a e in the task file asks the task's own agent to revise it")
  lua("require('taskbay.core').open(e2e.by_number(3))")
  keys("<Esc><Space>av")
  wait_for("Space a v opens task 3's file", "return vim.b.taskbay_task ~= nil and vim.b.taskbay_task.target.number == 3")
  keys("<Space>ae")
  wait_for("Space a e must ask for a revision", "return e2e.prompt_open() and vim.fn.mode() == 'i'")
  lua([[
    local shown
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_buf_get_name(buf):find("/.tasks/003-", 1, true) and vim.b[buf].taskbay_task then shown = true end
    end
    assert(shown and vim.t.taskbay_workspace == e2e.by_number(3).id, "The canonical task file opens in its own tab")
  ]])
  keys("Split it into two steps")
  wait_for("The request is typed into the prompt",
    "return vim.bo.filetype == 'snacks_input' and vim.api.nvim_get_current_line():find('two steps', 1, true) ~= nil")
  keys("<CR>")
  wait_for("The revision request must reach agent 3", [[
    local path = require("taskbay.core").directory(e2e.by_number(3)) .. "/paste.txt"
    local text = vim.uv.fs_stat(path) and table.concat(vim.fn.readfile(path), "\n") or ""
    return text:find("Split it into two steps", 1, true) ~= nil
  ]], 15000)
  lua([[
    local text = table.concat(vim.fn.readfile(require("taskbay.core").directory(e2e.by_number(3)) .. "/paste.txt"), "\n")
    assert(text:find("/.tasks/003-", 1, true) and text:find("Edit only the local task file", 1, true), text)
  ]])
  keys("<C-\\><C-n>")

  step("edit task 1's description and restart it with R in the panel")
  lua("require('taskbay.core').open(e2e.by_number(1))")
  keys("<Esc><Space>av")
  wait_for("Space a v opens task 1's file in its tab", [[
    local info = vim.b.taskbay_task
    return info ~= nil and info.target.number == 1 and vim.t.taskbay_workspace == e2e.by_number(1).id
  ]])
  keys("Go<CR>Also add a goodbye() alias.<Esc>:write<CR>")
  wait_for("Saving a started task points to restart", [[
    return _G.e2e_messages[#_G.e2e_messages]:find("R restarts project/1-add-a-farewell-function", 1, true) ~= nil
  ]])
  vim.fn.writefile({ "work from the first conversation" }, repo .. "-worktrees/task-1/kept-work.txt")
  local old_job = lua("return e2e.job(1).channel")
  keys("<Space>aw")
  wait_for("Panel", "return e2e.dashboard_row(1) ~= nil")
  lua("vim.api.nvim_win_set_cursor(0, { e2e.dashboard_row(1), 0 })")
  keys("R")
  wait_for("Restart asks before stopping a running agent", "local p = Snacks.picker.get()[1]; return p ~= nil and p:count() == 2")
  pick("Restart", "Restart with the current task")
  wait_for("Task 1 restarts in a new conversation", [[
    local job = e2e.job(1)
    return job ~= nil and job.channel ~= ... and not job.exited and job.sequence ~= nil and e2e.live() == 3
  ]], 10000, old_job)
  lua([[
    local id, terms = e2e.by_number(1).id, 0
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      if vim.t[tab].taskbay_workspace == id then
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
          if vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "terminal" then terms = terms + 1 end
        end
      end
    end
    assert(terms == 1, "The restarted agent replaces the old terminal in the task tab: " .. terms)
  ]])
  local restarted
  for _, event in ipairs(agents()) do
    if event.event == "started" then restarted = event end
  end
  assert(restarted.event == "started" and restarted.cwd:match("task%-1$") and not restarted.resumed, vim.inspect(restarted))
  assert(restarted.prompt:find("Also add a goodbye() alias.", 1, true), "The restart sends the edited description")
  assert(restarted.prompt:find("previous conversation already worked", 1, true),
    "The restarted prompt tells pi to pick up the worktree's existing work")
  assert(restarted.args[vim.fn.index(restarted.args, "--session-id") + 2]:match("%-r1$"), "A fresh session id")
  assert(uv.fs_stat(repo .. "-worktrees/task-1/kept-work.txt"), "Restarting keeps the worktree's changes")
  keys("<C-\\><C-n>")

  step("stop task 2 from the dashboard, then start the queued task 4")
  keys("<Esc><Space>aw")
  wait_for("Dashboard", "return e2e.dashboard_row(2) ~= nil")
  lua("vim.api.nvim_win_set_cursor(0, { e2e.dashboard_row(2), 0 })")
  keys("x")
  wait_for("Task 2 must stop and release its slot", [[
    local core = require("taskbay.core")
    local workspace = e2e.by_number(2)
    return e2e.job(2).exited and core.status(workspace) == "stopped" and e2e.live() == 2
      and not vim.uv.fs_stat(core.directory(workspace) .. "/owner.json")
  ]])
  assert(uv.fs_stat(repo .. "-worktrees/task-2/AGENT_RESULT.md"), "Stopping keeps the agent's work")
  keys("<Esc><Space>aw")
  wait_for("Dashboard", "return e2e.dashboard_row(4) ~= nil")
  lua("vim.api.nvim_win_set_cursor(0, { e2e.dashboard_row(4), 0 })")
  keys("p")
  wait_for("Task 4 must take the free slot", [[
    local job = e2e.job(4)
    return job ~= nil and not job.exited and job.outcome == "success" and e2e.live() == 3
  ]], 10000)
  assert(not uv.fs_stat(repo .. "-worktrees/task-4/AGENT_RESULT.md"), "The scripted agent was told to change nothing")
  wait_for("A settled agent that changed nothing is flagged", [[
    local core = require("taskbay.core")
    return core.status(e2e.by_number(4)) == "no changes" and core.status(e2e.by_number(3)) == "idle"
  ]])
  keys("<C-\\><C-n><Esc><Space>aw")
  wait_for("Dashboard flags task 4", [[
    local row = e2e.dashboard_row(4)
    return row ~= nil and e2e.float_lines("Task Workspaces")[row]:find("no changes", 1, true) ~= nil
  ]])
  lua("vim.api.nvim_win_set_cursor(0, { e2e.dashboard_row(4), 0 })")
  keys("c")
  wait_for("c asks task 4's own agent to continue and submits it", [[
    local core = require("taskbay.core")
    local path = core.directory(e2e.by_number(4)) .. "/paste.txt"
    local text = vim.uv.fs_stat(path) and table.concat(vim.fn.readfile(path, "b"), "\n") or ""
    return text:find("left the worktree unchanged", 1, true) ~= nil and text:find("\27[201~\r", 1, true) ~= nil
  ]])
  lua([[
    assert(e2e.float_lines("Task Workspaces"), "c keeps the dashboard open")
    vim.api.nvim_win_set_cursor(0, { e2e.dashboard_row(2), 0 })
  ]])
  keys("c")
  wait_for("c refuses a stopped agent", [[
    return _G.e2e_messages[#_G.e2e_messages]:find("before continuing it", 1, true) ~= nil
  ]])
  keys("q")

  step("resume task 2 after another agent stops")
  lua("require('taskbay.core').stop(e2e.by_number(1))")
  wait_for("Task 1 stops", "return e2e.job(1).exited and e2e.live() == 2")
  lua([[
    local tasks = require("taskbay.store")
    local task = tasks.get(e2e.by_number(2))
    tasks.update(e2e.by_number(2), task.title, task.body .. "\n\nAlso document farewell().")
    require("taskbay.core").open(e2e.by_number(2))
  ]])
  keys("<Esc><Space>ap")
  wait_for("Resuming after an edit sends the updated task into the conversation", [[
    local path = require("taskbay.core").directory(e2e.by_number(2)) .. "/paste.txt"
    local text = vim.uv.fs_stat(path) and table.concat(vim.fn.readfile(path, "b"), "\n") or ""
    return text:find("The task description was updated", 1, true) ~= nil
      and text:find("Also document farewell().", 1, true) ~= nil and text:find("\27[201~\r", 1, true) ~= nil
  ]])
  wait_for("Space a p resumes task 2", [[
    local job = e2e.job(2)
    return job ~= nil and not job.exited and job.sequence ~= nil and e2e.live() == 3
  ]])
  local resumed
  for _, event in ipairs(agents()) do
    if event.event == "started" and event.resumed then resumed = event end
  end
  assert(resumed and resumed.cwd:match("task%-2$") and resumed.prompt == "", "Resume without replaying the task")

  step(":TaskbayQuit stops every agent and keeps worktrees")
  local pids = {}
  for _, event in ipairs(agents()) do
    if event.event == "started" then pids[#pids + 1] = event.pid end
  end
  keys("<C-\\><C-n><Esc>:TaskbayQuit<CR>")
  wait_for(":TaskbayQuit must refuse while a file has unsaved edits",
    "return _G.e2e_messages[#_G.e2e_messages]:find('Save or discard modified files', 1, true) ~= nil")
  assert(H.exited() == nil, "Unsaved edits must keep the editor open")
  lua([[
    local buf = vim.fn.bufnr(e2e.by_number(2).path .. "/app.py")
    assert(vim.bo[buf].modified)
    vim.api.nvim_buf_call(buf, function() vim.cmd("silent write") end)
  ]])
  keys(":TaskbayQuit<CR>")
  wait_for(":TaskbayQuit must ask before stopping agents", [[
    local p = Snacks.picker.get()[1]
    return p ~= nil and p:count() == 2
  ]])
  pick("Stop agents", "Stop agents and quit")
  assert(vim.wait(8000, function() return H.exited() ~= nil end, 25), "TaskbayQuit must exit the editor")
  for _, pid in ipairs(pids) do
    assert(vim.wait(2000, function() return not uv.kill(pid, 0) end, 25), "pi process " .. pid .. " survived :TaskbayQuit")
  end
  for number = 1, 3 do
    assert(uv.fs_stat(repo .. "-worktrees/task-" .. number .. "/AGENT_RESULT.md"), "Worktree " .. number .. " kept")
  end

  step("a new editor restores every workspace without starting agents")
  local before_restart = #agents()
  boot()
  keys("<Space>aw")
  wait_for("Dashboard lists the four saved workspaces", [[
    local text = table.concat(e2e.float_lines("Task Workspaces") or {}, "\n")
    return text:find("0 of 3 agents running", 1, true) ~= nil and text:find("4 tasks", 1, true) ~= nil
  ]])
  lua([[
    local core = require("taskbay.core")
    for number = 1, 4 do
      assert(core.status(e2e.by_number(number)) == "stopped", "Task " .. number .. " restored as stopped")
    end
  ]])
  vim.wait(300)
  assert(#agents() == before_restart, "Restoring workspaces must not start pi")
  keys("<C-\\><C-n><Esc><Space>aw")
  wait_for("Workspace panel must list the restored workspaces", "return e2e.dashboard_row(1) ~= nil")
  keys("v")
  wait_for("v opens task 1's file from the panel",
    "return vim.b.taskbay_task ~= nil and vim.b.taskbay_task.target.number == 1")
  keys("<Esc><Space>aw")
  wait_for("Panel", "return e2e.dashboard_row(1) ~= nil")
  lua("vim.api.nvim_win_set_cursor(0, { e2e.dashboard_row(1), 0 })")
  keys("<CR>")
  wait_for("Enter opens a stopped task's tab without starting pi",
    "return require('taskbay.core').current() == e2e.by_number(1) and (e2e.job(1) or { exited = true }).exited")
  assert(#agents() == before_restart, "Opening a stopped task must not start pi")
  keys("<Esc><Space>ap")
  wait_for("Space a p in the task tab resumes task 1", [[
    local job = e2e.job(1)
    return job ~= nil and not job.exited and job.sequence ~= nil and require("taskbay.core").current() == e2e.by_number(1)
  ]])
  lua("require('taskbay.core').stop(e2e.by_number(1))")
  wait_for("Task 1 stops", "return e2e.job(1).exited")
  keys("<C-\\><C-n><Esc><Space>aw")
  wait_for("Dashboard", "return e2e.dashboard_row(3) ~= nil")
  lua("vim.api.nvim_win_set_cursor(0, { e2e.dashboard_row(3), 0 })")
  keys("p")
  wait_for("p resumes task 3 in the new editor", [[
    local job = e2e.job(3)
    return job ~= nil and not job.exited and job.sequence ~= nil and require("taskbay.core").current() == e2e.by_number(3)
  ]])
  local last = agents()[#agents()]
  assert(last.event == "started" and last.resumed and last.cwd:match("task%-3$") and last.prompt == "",
    "Resume the saved session after a restart: " .. vim.inspect(last))
  assert(last.args[vim.fn.index(last.args, "--session") + 2]:find("session.jsonl", 1, true))
  lua("require('taskbay.core').stop(e2e.by_number(3))")
  wait_for("Task 3 stops", "return e2e.job(3).exited")
  keys("<Esc><Space>aw")
  wait_for("Dashboard", "return e2e.dashboard_row(3) ~= nil")
  lua("vim.api.nvim_win_set_cursor(0, { e2e.dashboard_row(3), 0 })")

  step("m in the panel finishes task 3: stops pi, commits, merges into main, marks finished")
  keys("m")
  wait_for("Finish asks to commit and merge", [[
    local p = Snacks.picker.get()[1]
    return p ~= nil and p:count() == 2
  ]])
  pick("Commit", "Commit and merge")
  wait_for("Task 3 merges and is marked finished", [[
    local core = require("taskbay.core")
    local workspace = e2e.by_number(3)
    return workspace.finished ~= nil and core.status(workspace) == "finished"
  ]], 15000)
  assert(uv.fs_stat(repo .. "/AGENT_RESULT.md"), "The finished task's work lands in the main checkout")
  assert(uv.fs_stat(repo .. "-worktrees/task-3/AGENT_RESULT.md"), "Finishing keeps the worktree")
  keys("<Esc><Space>aw")
  wait_for("The finished task is flagged in the dashboard, sorted last", [[
    local row3 = e2e.dashboard_row(3)
    local finished = row3 ~= nil and e2e.float_lines("Task Workspaces")[row3]:find("finished", 1, true)
    return finished ~= nil and row3 > math.max(e2e.dashboard_row(1) or 0, e2e.dashboard_row(2) or 0,
      e2e.dashboard_row(4) or 0)
  ]])
  keys("q")

  keys("<Esc>:qa!<CR>")
  assert(vim.wait(5000, function() return H.exited() ~= nil end, 25), "Editor must exit")
end)

