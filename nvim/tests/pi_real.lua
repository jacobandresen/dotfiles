-- Opt-in end-to-end run with the REAL pi binary, the pinned extension and a LOCAL model.
-- Writes three tasks with Space a n, picks them with Space a i, starts all three at once,
-- and waits until each agent has implemented its own task in its own worktree.
-- Only a model whose provider baseUrl is on this machine is accepted; the isolated pi
-- config has no credentials, so hosted providers cannot be reached.
--   make test-pi-real   (PI_REAL_MODEL=ollama/<id>, PI_REAL_TIMEOUT=<seconds>, PI_REAL_FOLLOWUPS=<n>)
local uv = vim.uv
local root = vim.fn.getcwd()
local function fail(message)
  io.stderr:write("pi real: " .. message .. "\n")
  vim.cmd("cquit 1")
end
if vim.fn.executable("pi") ~= 1 then fail("pi is not installed") end
if not uv.fs_stat(root .. "/nvim/pi/node_modules/pi-subagents/bundle/index.js") then
  fail("pinned pi extension missing: run :PiTaskSetup")
end

-- Resolve and verify the local model before anything starts.
local function json(path) return vim.json.decode(table.concat(vim.fn.readfile(path), "\n")) end
local settings, models = json(root .. "/pi/agent/settings.json.template"), json(root .. "/pi/agent/models.json")
local wanted = vim.env.PI_REAL_MODEL or (settings.defaultProvider .. "/" .. settings.defaultModel)
local provider_name, model_id = wanted:match("^([^/]+)/(.+)$")
local provider = provider_name and models.providers[provider_name]
if not provider then fail(wanted .. ": provider is not defined in pi/agent/models.json") end
local host = provider.baseUrl:match("^https?://%[?([^/%]]-)%]?:%d+") or provider.baseUrl:match("^https?://([^/:]+)")
if not vim.tbl_contains({ "127.0.0.1", "localhost", "::1" }, host) then
  fail(wanted .. " is not a local model (baseUrl " .. provider.baseUrl .. ")")
end
local listed = false
for _, model in ipairs(provider.models) do listed = listed or model.id == model_id end
if not listed then fail(wanted .. " is not listed in pi/agent/models.json") end
if provider_name == "ollama" then
  local tags = vim.system({ "curl", "-sf", "-m", "5", (provider.baseUrl:gsub("/v1/?$", "")) .. "/api/tags" },
    { text = true }):wait()
  if tags.code ~= 0 then fail("Ollama is not reachable at " .. provider.baseUrl) end
  local pulled = false
  for _, model in ipairs(vim.json.decode(tags.stdout).models) do
    pulled = pulled or model.name == model_id or model.name == model_id .. ":latest"
  end
  if not pulled then fail(wanted .. " is not pulled in Ollama (ollama pull " .. model_id .. ")") end
end

-- Isolated pi config: your settings template and local model catalog, no credentials.
local agent_dir = assert(uv.fs_mkdtemp(uv.os_tmpdir() .. "/pi-real-agent-XXXXXX"))
settings.defaultProvider, settings.defaultModel = provider_name, model_id
if vim.env.PI_REAL_THINKING then
  settings.defaultThinkingLevel = vim.env.PI_REAL_THINKING
  settings.modelThinkingLevels = {}
end
settings.lastChangelogVersion = vim.trim(vim.fn.system({ "pi", "--version" }))
vim.fn.writefile({ vim.json.encode(settings) }, agent_dir .. "/settings.json")
vim.fn.writefile(vim.fn.readfile(root .. "/pi/agent/models.json"), agent_dir .. "/models.json")

local H = dofile(root .. "/nvim/tests/pi_harness.lua")({
  stub = false, name = "pi-real", rpc_timeout = 120000, cleanup = { agent_dir }, env = { PI_CODING_AGENT_DIR = agent_dir },
})
local repo, sh, lua, keys, wait_for, pick, step = H.repo, H.sh, H.lua, H.keys, H.wait_for, H.pick, H.step
local timeout = tonumber(vim.env.PI_REAL_TIMEOUT or "1800") * 1000
local words = { "alpha", "bravo", "charlie" }
local max_followups = tonumber(vim.env.PI_REAL_FOLLOWUPS or "2")
local function result_path(number) return repo .. "-worktrees/task-" .. number .. "/result-" .. number .. ".txt" end
local function read(path) return uv.fs_stat(path) and vim.trim(table.concat(vim.fn.readfile(path), "\n")) or nil end

H.run("pi real: three tasks implemented concurrently by local " .. wanted, function()
  print("pi real: using local model " .. wanted .. " (timeout " .. timeout / 1000 .. "s)")
  H.boot()
  step("write three tasks with Space a n")
  for number, word in ipairs(words) do
    keys("<Esc><Space>an")
    wait_for("Space a n opens a blank task", [[return vim.bo.buftype == "acwrite" and vim.fn.mode() == "i"]])
    keys(("Create result-%d.txt<CR><CR>Create a file named result-%d.txt in the repository root. "
      .. "Its entire content must be the single word %s followed by a newline. "
      .. "Do not change or create any other file. Do not run tests.<Esc>:write<CR>"):format(number, number, word))
    wait_for("Task " .. number .. " is saved", [[
      local info = vim.b.pi_issue_draft
      return info ~= nil and info.target.number == ... and not vim.bo.modified
    ]], 8000, number)
  end

  step("pick all three and start them")
  keys("<Esc><Space>ai")
  wait_for("Space a i lists three tasks", "local p = Snacks.picker.get()[1]; return p ~= nil and p:count() == 3")
  keys("<Tab><Tab><Tab>")
  wait_for("Three tasks selected", "return #Snacks.picker.get()[1]:selected() == 3")
  keys("<CR>")
  wait_for("Three real pi processes start and report", [[
    if e2e.live() ~= 3 then return false end
    for number = 1, 3 do
      if not e2e.job(number) or not e2e.job(number).sequence then return false end
    end
    return true
  ]], 60000)
  lua([[
    for number = 1, 3 do
      local job = e2e.job(number)
      assert(job.model == ..., ("Task %d reports model %s"):format(number, tostring(job.model)))
      assert(not vim.tbl_contains(job.argv, "--model"), "The configured default model is used")
    end
  ]], wanted)

  step("wait for all three agents to implement their tasks")
  -- A small local model sometimes ends its turn after only thinking; like a user would,
  -- press c on its dashboard row (at most PI_REAL_FOLLOWUPS times per agent, default 2).
  local peak, started_at, deadline, last_report = 0, uv.now(), uv.now() + timeout, 0
  local followups, nudged_at = { 0, 0, 0 }, {}
  while true do
    for number = 1, 3 do
      local settled = lua([[
        local job = e2e.job(...)
        return { idle = job.activity == "idle" and job.outcome ~= nil and job.outcome ~= "unknown", sequence = job.sequence }
      ]], number)
      if settled.idle and not read(result_path(number)) and followups[number] < max_followups
        and (nudged_at[number] or -1) < settled.sequence then
        followups[number] = followups[number] + 1
        nudged_at[number] = settled.sequence + 1
        print(("pi real: task %d settled without its file; follow-up %d"):format(number, followups[number]))
        keys("<C-\\><C-n><Esc><Space>aw")
        wait_for("Dashboard", "return e2e.dashboard_row(...) ~= nil", 30000, number)
        lua("vim.api.nvim_win_set_cursor(0, { e2e.dashboard_row(...), 0 })", number)
        keys("c")
        wait_for("Dashboard c continues task " .. number, [[
          return _G.e2e_messages[#_G.e2e_messages]:find("to continue", 1, true) ~= nil
        ]], 30000)
        keys("q")
        vim.wait(1500)
      end
    end
    local state = lua([[
      local state = { working = 0, live = e2e.live(), done = 0, waiting = 0 }
      for number = 1, 3 do
        local job = e2e.job(number)
        if job.activity == "working" then state.working = state.working + 1 end
        if job.activity == "waiting" then state.waiting = state.waiting + 1 end
        if job.activity == "idle" and job.outcome ~= nil and job.outcome ~= "unknown" then state.done = state.done + 1 end
      end
      return state
    ]])
    for number = 1, 3 do
      local pending = not read(result_path(number)) and followups[number] < max_followups
      if pending and state.done == 3 then state.done = 2 end
    end
    peak = math.max(peak, state.working)
    assert(state.live == 3, "An agent exited early\n" .. H.messages())
    assert(state.waiting == 0, "An agent is waiting for terminal input\n" .. H.messages())
    local written = 0
    for number = 1, 3 do if read(result_path(number)) then written = written + 1 end end
    if state.done == 3 then break end
    assert(uv.now() < deadline, ("Timed out: %d/3 settled, %d/3 files written\n"):format(state.done, written)
      .. H.messages())
    if uv.now() - last_report > 30000 then
      last_report = uv.now()
      print(("pi real: %4ds  working %d  settled %d/3  files %d/3"):format(
        (uv.now() - started_at) / 1000, state.working, state.done, written))
    end
    vim.wait(1000)
    uv.update_time()
  end
  print(("pi real: all agents settled after %ds; peak concurrently working: %d; follow-ups needed: %s"):format(
    (uv.now() - started_at) / 1000, peak, table.concat(followups, "/")))
  assert(peak == 3, "All three agents must work at the same time; peak was " .. peak)

  step("check each agent's work and that only the local model answered")
  for number, word in ipairs(words) do
    local content = read(result_path(number))
    assert(content == word, ("Task %d: expected result-%d.txt to contain %q, found %s\n"):format(
      number, number, word, vim.inspect(content)) .. H.messages())
    for other = 1, 3 do
      if other ~= number then
        assert(not uv.fs_stat(repo .. "-worktrees/task-" .. number .. "/result-" .. other .. ".txt"),
          "Task " .. number .. " did another task's work")
      end
    end
    local providers = {}
    for _, line in ipairs(vim.fn.readfile(lua("return e2e.by_number(...).session_file", number))) do
      for name in line:gmatch('"provider"%s*:%s*"([^"]+)"') do providers[name] = true end
    end
    assert(vim.deep_equal(providers, { [provider_name] = true }),
      "Task " .. number .. " session used providers " .. vim.inspect(vim.tbl_keys(providers)))
  end
  assert(sh({ "git", "status", "--porcelain" }) == "?? .tasks/", "The main checkout must stay untouched")

  step(":PiQuit stops the agents")
  keys("<C-\\><C-n><Esc>:PiQuit<CR>")
  wait_for(":PiQuit asks", "local p = Snacks.picker.get()[1]; return p ~= nil and p:count() == 2")
  pick("Stop agents", "Stop agents and quit")
  assert(vim.wait(15000, function() return H.exited() ~= nil end, 50), "PiQuit must exit the editor")
end)
