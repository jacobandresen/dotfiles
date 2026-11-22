-- End-to-end: write tasks, pick three, run three pi agents at once, using the real
-- LazyVim config and real keystrokes. pi is replaced by a scripted, offline stand-in.
-- Run from the repository root: timeout 180 nvim --headless -u NONE -i NONE -l nvim/tests/pi_e2e.lua
local uv = vim.uv
local H = dofile(vim.fn.getcwd() .. "/nvim/tests/pi_harness.lua")()
local repo, release, sh, lua, keys, wait_for, pick, step, agents, boot =
  H.repo, H.release, H.sh, H.lua, H.keys, H.wait_for, H.pick, H.step, H.agents, H.boot

local tasks = {
  { title = "Add a farewell function", body = "Add farewell() next to greet() in app.py." },
  { title = "Document the greeting API", body = "Describe greet() in README.md." },
  { title = "Add greeting tests", body = "Cover greet() with a unit test." },
  { title = "Fourth queued task", body = "Waits for a free agent slot. [no changes]" },
}

H.run("pi e2e: wrote 4 tasks, ran 3 agents at once, queued a 4th, sent context, revised, stopped, resumed, quit and restored", function()
  boot()

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
      local info = vim.b.pi_issue_draft
      return info ~= nil and info.target.number == ... and vim.bo.buftype == "" and not vim.bo.modified
    ]], 8000, index)
  end
  step("write a fourth task with :PiTaskNew")
  keys("<Esc>:PiTaskNew " .. tasks[4].title .. "<CR>")
  wait_for(":PiTaskNew <title> must create and open task 4",
    "return vim.b.pi_issue_draft ~= nil and vim.b.pi_issue_draft.target.number == 4")
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

  step("pick three tasks with Space a i and Tab, then start them")
  keys("<Esc><Space>ai")
  wait_for("Space a i must list the four local tasks",
    "local p = Snacks.picker.get()[1]; return p ~= nil and p:count() == 4")
  keys("<Tab><Tab><Tab>")
  wait_for("Tab must select three tasks", "return #Snacks.picker.get()[1]:selected() == 3")
  lua([[
    local numbers = {}
    for _, item in ipairs(Snacks.picker.get()[1]:selected()) do numbers[#numbers + 1] = item.number end
    table.sort(numbers)
    assert(vim.deep_equal(numbers, { 1, 2, 3 }), vim.inspect(numbers))
  ]])
  keys("<CR>")
  lua([[assert(not e2e.prompt_open() and not e2e.float_lines("Review Task Launch"), "Enter starts without prompts")]])
  wait_for("Three pi agents must be working at the same time", [[
    for number = 1, 3 do
      local job = e2e.job(number)
      if not job or job.exited or job.activity ~= "working" then return false end
    end
    return e2e.live() == 3
  ]], 15000)
  wait_for("Launch must report three started",
    "return table.concat(_G.e2e_messages, '\\n'):find('3 prepared; 3 started', 1, true) ~= nil")

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
    local core = require("util.pi_issues")
    local tabs = vim.api.nvim_list_tabpages()
    assert(#tabs == 4, "One code tab per task plus the original: " .. #tabs)
    local owned = {}
    for _, tab in ipairs(tabs) do
      local id = vim.t[tab].pi_issue
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
      assert(tabline:find("project/task-" .. number .. " working", 1, true), tabline)
    end
  ]])
  assert(sh({ "git", "status", "--porcelain" }) == "?? .tasks/", "The main checkout must stay untouched")

  step("dashboard shows three live agents")
  keys("<C-\\><C-n><Space>aw")
  wait_for("Space a w must open the dashboard", "return e2e.float_lines('Task Workspaces') ~= nil")
  lua([[
    local text = table.concat(e2e.float_lines("Task Workspaces"), "\n")
    assert(text:find("3 active / 3 slots", 1, true), text)
    for number = 1, 3 do
      assert(e2e.float_lines("Task Workspaces")[e2e.dashboard_row(number)]:find("working", 1, true), text)
    end
  ]])
  keys("q")

  step("Space a a and dashboard digits jump to a running task's pi")
  keys("<Esc><Space>aa")
  wait_for("Space a a lists the running tasks", "local p = Snacks.picker.get()[1]; return p ~= nil and p:count() == 3")
  pick("task-3", "project/task-3")
  wait_for("Enter jumps into task 3's pi terminal", [[
    local core = require("util.pi_issues")
    return core.current() == e2e.by_number(3) and vim.api.nvim_get_current_buf() == e2e.job(3).buf
  ]])
  keys("<C-\\><C-n><Space>aw")
  wait_for("Dashboard numbers its rows", "local row = e2e.dashboard_row(2); return row ~= nil and e2e.float_lines('Task Workspaces')[row]:match('^ 2 ') ~= nil")
  keys("2")
  wait_for("2 jumps into task 2's pi terminal", [[
    local core = require("util.pi_issues")
    return core.current() == e2e.by_number(2) and vim.api.nvim_get_current_buf() == e2e.job(2).buf
      and not e2e.float_lines("Task Workspaces")
  ]])
  keys("<C-\\><C-n>")

  step("a fourth task is prepared but must wait for a slot")
  keys("<Esc><Space>ai")
  wait_for("Picker must reopen", "local p = Snacks.picker.get()[1]; return p ~= nil and p:count() == 4")
  keys("Fourth")
  wait_for("Search must narrow to task 4", [[
    local p = Snacks.picker.get()[1]
    return p:current() ~= nil and p:current().number == 4 and #p:selected() == 0
  ]])
  keys("<C-b>")
  wait_for("Ctrl-b must ask for the base ref", "return e2e.prompt_open()")
  keys("<CR>")
  wait_for("Ctrl-b must show the launch review", "return e2e.float_lines('Review Task Launch') ~= nil")
  lua([[
    local text = table.concat(e2e.float_lines("Review Task Launch"), "\n")
    for _, needle in ipairs({ "Base: HEAD", "/task-4", "task/4", "Fourth queued task", "Limit: 3" }) do
      assert(text:find(needle, 1, true), "Launch review is missing " .. needle .. ":\n" .. text)
    end
  ]])
  keys("s")
  wait_for("The fourth task must be prepared without starting",
    "return table.concat(_G.e2e_messages, '\\n'):find('1 prepared; 0 started', 1, true) ~= nil")
  lua([[
    local core = require("util.pi_issues")
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
    local core = require("util.pi_issues")
    for number = 1, 3 do
      assert(core.status(e2e.by_number(number)) == "idle")
      assert(core.jobs[e2e.by_number(number).id].model == "e2e/scripted-agent")
    end
  ]])

  step("Space a s sends context to the agent of the current tab only")
  lua([[
    local core = require("util.pi_issues")
    core.open(e2e.by_number(2))
    vim.cmd.edit(e2e.by_number(2).path .. "/app.py")
    vim.api.nvim_buf_set_lines(0, -1, -1, false, { "# context for task two" })
  ]])
  keys("<Esc><Space>as")
  wait_for("Context must reach agent 2", [[
    local path = require("util.pi_issues").directory(e2e.by_number(2)) .. "/paste.txt"
    return vim.uv.fs_stat(path) ~= nil and table.concat(vim.fn.readfile(path), "\n"):find("context for task two", 1, true) ~= nil
  ]])
  lua([[
    local core = require("util.pi_issues")
    for _, number in ipairs({ 1, 3 }) do
      assert(not vim.uv.fs_stat(core.directory(e2e.by_number(number)) .. "/paste.txt"), "Context leaked to " .. number)
    end
  ]])
  keys("<C-\\><C-n>")

  step("Space a e asks the task's own agent to revise its task file")
  lua("require('util.pi_issues').open(e2e.by_number(3))")
  keys("<Esc><Space>ae")
  wait_for("Space a e must open the task and ask for a revision", "return e2e.prompt_open()")
  lua([[
    local shown
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_buf_get_name(buf):find("/.tasks/003-", 1, true) and vim.b[buf].pi_issue_draft then shown = true end
    end
    assert(shown and vim.t.pi_issue == e2e.by_number(3).id, "Space a e opens the canonical task file in its own tab")
  ]])
  keys("Split it into two steps<CR>")
  wait_for("The revision request must reach agent 3", [[
    local path = require("util.pi_issues").directory(e2e.by_number(3)) .. "/paste.txt"
    local text = vim.uv.fs_stat(path) and table.concat(vim.fn.readfile(path), "\n") or ""
    return text:find("Split it into two steps", 1, true) ~= nil
  ]])
  lua([[
    local text = table.concat(vim.fn.readfile(require("util.pi_issues").directory(e2e.by_number(3)) .. "/paste.txt"), "\n")
    assert(text:find("/.tasks/003-", 1, true) and text:find("Edit only the local task file", 1, true), text)
  ]])
  keys("<C-\\><C-n>")

  step("stop task 2 from the dashboard, then start the queued task 4")
  keys("<Esc><Space>aw")
  wait_for("Dashboard", "return e2e.dashboard_row(2) ~= nil")
  lua("vim.api.nvim_win_set_cursor(0, { e2e.dashboard_row(2), 0 })")
  keys("x")
  wait_for("Stop must ask for confirmation", [[
    local p = Snacks.picker.get()[1]
    return p ~= nil and p:count() == 2
  ]])
  pick("Stop pi", "Stop pi; keep worktree and session")
  wait_for("Task 2 must stop and release its slot", [[
    local core = require("util.pi_issues")
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
    local core = require("util.pi_issues")
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
    local core = require("util.pi_issues")
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
  lua("require('util.pi_issues').stop(e2e.by_number(1))")
  wait_for("Task 1 stops", "return e2e.job(1).exited and e2e.live() == 2")
  lua("require('util.pi_issues').open(e2e.by_number(2))")
  keys("<Esc><Space>ap")
  wait_for("Space a p resumes task 2", [[
    local job = e2e.job(2)
    return job ~= nil and not job.exited and job.sequence ~= nil and e2e.live() == 3
  ]])
  local resumed
  for _, event in ipairs(agents()) do
    if event.event == "started" and event.resumed then resumed = event end
  end
  assert(resumed and resumed.cwd:match("task%-2$") and resumed.prompt == "", "Resume without replaying the task")

  step(":PiQuit stops every agent and keeps worktrees")
  local pids = {}
  for _, event in ipairs(agents()) do
    if event.event == "started" then pids[#pids + 1] = event.pid end
  end
  keys("<C-\\><C-n><Esc>:PiQuit<CR>")
  wait_for(":PiQuit must refuse while a file has unsaved edits",
    "return _G.e2e_messages[#_G.e2e_messages]:find('Save or discard modified files', 1, true) ~= nil")
  assert(H.exited() == nil, "Unsaved edits must keep the editor open")
  lua([[
    local buf = vim.fn.bufnr(e2e.by_number(2).path .. "/app.py")
    assert(vim.bo[buf].modified)
    vim.api.nvim_buf_call(buf, function() vim.cmd("silent write") end)
  ]])
  keys(":PiQuit<CR>")
  wait_for(":PiQuit must ask before stopping agents", [[
    local p = Snacks.picker.get()[1]
    return p ~= nil and p:count() == 2
  ]])
  pick("Stop agents", "Stop agents and quit")
  assert(vim.wait(8000, function() return H.exited() ~= nil end, 25), "PiQuit must exit the editor")
  for _, pid in ipairs(pids) do
    assert(vim.wait(2000, function() return not uv.kill(pid, 0) end, 25), "pi process " .. pid .. " survived :PiQuit")
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
    return text:find("0 active / 3 slots", 1, true) ~= nil and text:find("4 workspaces", 1, true) ~= nil
  ]])
  lua([[
    local core = require("util.pi_issues")
    for number = 1, 4 do
      assert(core.status(e2e.by_number(number)) == "stopped", "Task " .. number .. " restored as stopped")
    end
  ]])
  vim.wait(300)
  assert(#agents() == before_restart, "Restoring workspaces must not start pi")
  keys("q<Space>ai")
  wait_for("Task picker", "local p = Snacks.picker.get()[1]; return p ~= nil and p:count() == 4")
  keys("<C-o>")
  wait_for("Ctrl-o opens task 1's file", "return vim.b.pi_issue_draft ~= nil and vim.b.pi_issue_draft.target.number == 1")
  keys("<Esc><Space>ag")
  wait_for("Space a g in the task buffer resumes task 1", [[
    local job = e2e.job(1)
    return job ~= nil and not job.exited and job.sequence ~= nil and require("util.pi_issues").current() == e2e.by_number(1)
  ]])
  lua("require('util.pi_issues').stop(e2e.by_number(1))")
  wait_for("Task 1 stops", "return e2e.job(1).exited")
  keys("<C-\\><C-n><Esc><Space>aw")
  wait_for("Dashboard", "return e2e.dashboard_row(3) ~= nil")
  lua("vim.api.nvim_win_set_cursor(0, { e2e.dashboard_row(3), 0 })")
  keys("p")
  wait_for("p resumes task 3 in the new editor", [[
    local job = e2e.job(3)
    return job ~= nil and not job.exited and job.sequence ~= nil and require("util.pi_issues").current() == e2e.by_number(3)
  ]])
  local last = agents()[#agents()]
  assert(last.event == "started" and last.resumed and last.cwd:match("task%-3$") and last.prompt == "",
    "Resume the saved session after a restart: " .. vim.inspect(last))
  assert(last.args[vim.fn.index(last.args, "--session") + 2]:find("session.jsonl", 1, true))
  lua("require('util.pi_issues').stop(e2e.by_number(3))")
  wait_for("Task 3 stops", "return e2e.job(3).exited")
  keys("<Esc>:qa!<CR>")
  assert(vim.wait(5000, function() return H.exited() ~= nil end, 25), "Editor must exit")
end)

