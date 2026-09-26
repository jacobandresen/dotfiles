-- Docker explorer: a Snacks picker drawn like the file explorer (Turbo Vision
-- sidebar, tree lines) with Docker Desktop's sections - Containers grouped by
-- compose project/service (or state, network, image), Images, Volumes and
-- Networks. The window layout is registered in plugins/ui.lua; ? lists keys.
local actions = require("util.compose.actions")
local docker = require("util.compose.docker")
local logs = require("util.compose.logs")
local views = require("util.compose.views")

local M = {}

-- format -----------------------------------------------------------------------

local state_hl = {
  running = "SnacksPickerDockerRunning",
  paused = "SnacksPickerDockerPaused",
  restarting = "SnacksPickerDockerPaused",
  created = "SnacksPickerDockerExited",
  exited = "SnacksPickerDockerExited",
  dead = "SnacksPickerDockerDead",
}

---@param c compose.Container
local function container_state(c)
  if c.status:find("unhealthy") then
    return "unhealthy", "SnacksPickerDockerDead"
  elseif c.state == "exited" then
    local code = c.status:match("%((%d+)%)") or "?"
    -- 143: stopped with SIGTERM, i.e. a normal `docker stop`
    local clean = code == "0" or code == "143"
    return "exit " .. code, clean and state_hl.exited or "SnacksPickerDockerDead"
  elseif c.state == "running" then
    local stats = docker.state.stats[c.id]
    if stats then
      return stats.cpu, state_hl.running
    end
    return c.status:find("%(healthy%)") and "healthy" or "up", state_hl.running
  end
  return c.state, state_hl[c.state] or state_hl.exited
end

-- the dot of a group: green when all run, cyan when some do, grey when none
local function group_hl(item)
  if item.total == 0 then
    return state_hl.exited
  end
  return item.running == item.total and state_hl.running or item.running > 0 and state_hl.paused or state_hl.exited
end

local function cpu_sum(list)
  local sum, any = 0, false
  for _, c in ipairs(list) do
    local s = docker.state.stats[c.id]
    if s and c.state == "running" then
      sum, any = sum + (tonumber(s.cpu:match("[%d.]+")) or 0), true
    end
  end
  return any and ("%.1f%%"):format(sum) or nil
end

local right = {}

function right.project(item)
  if item.total == 0 then
    return { "not created", "SnacksPickerTotals" }
  end
  local cpu = cpu_sum(item.containers)
  return { ("%s%d/%d"):format(cpu and cpu .. "  " or "", item.running, item.total), "SnacksPickerTotals" }
end
right.service = right.project

function right.group(item)
  if item.containers then
    return right.project(item)
  end
  return { tostring(item.count), "SnacksPickerTotals" }
end

function right.container(item)
  return { container_state(item.container) }
end

function right.image(item)
  return { item.image.size, "SnacksPickerTotals" }
end

function right.volume(item)
  return { item.volume.size ~= "N/A" and item.volume.size or "", "SnacksPickerTotals" }
end

function right.network(item)
  local n = #item.containers
  return { n > 0 and ("%s  %d"):format(item.network.driver, n) or item.network.driver, "SnacksPickerTotals" }
end

function M.format(item, picker)
  local ret = {} ---@type snacks.picker.Highlight[]
  vim.list_extend(ret, Snacks.picker.format.tree(item, picker))
  if item.dir then
    ret[#ret + 1] = { item.open and "▾ " or "▸ ", "SnacksPickerTree" }
  end
  if item.kind == "container" then
    local _, hl = container_state(item.container)
    ret[#ret + 1] = { "● ", hl }
    ret[#ret + 1] = { item.label }
  elseif item.containers and item.kind ~= "volume" and item.kind ~= "network" then
    ret[#ret + 1] = { "● ", group_hl(item) }
    ret[#ret + 1] = { item.label, "SnacksPickerDirectory" }
  elseif item.kind == "group" then
    ret[#ret + 1] = { item.label, "SnacksPickerDirectory" }
  else
    -- images, volumes, networks: unused ones dimmed like Docker Desktop
    ret[#ret + 1] = { item.label, item.used and "SnacksPickerList" or "SnacksPickerDockerExited" }
  end
  local r = right[item.kind](item)
  local virt = { r, { " " } }
  -- the log icon marks rows with an open log buffer
  local key = logs.target(item)
  if key and logs.is_open(key) then
    table.insert(virt, 1, { logs.icon .. " ", "SnacksPickerIcon" })
  end
  ret[#ret + 1] = { col = 0, virt_text = virt, virt_text_pos = "right_align", hl_mode = "combine" }
  return ret
end

-- polling ------------------------------------------------------------------------

-- `docker ps` and friends every 2s (stats every 4s: it takes ~1s), redrawing
-- only when the output changed
local timer ---@type uv.uv_timer_t?

local function watch(picker)
  timer = timer or assert(vim.uv.new_timer())
  local busy, tick = false, 0
  timer:start(2000, 2000, vim.schedule_wrap(function()
    if busy or picker.closed then
      return
    end
    busy, tick = true, tick + 1
    local kinds = vim.deepcopy(views.needs[picker.opts.view])
    if picker.opts.view == "containers" and tick % 2 == 0 then
      table.insert(kinds, "stats")
    end
    docker.load(kinds, function(changed)
      busy = false
      if changed then
        actions.refresh(picker)
      end
    end)
  end))
end

-- source -------------------------------------------------------------------------

local function key(action, desc)
  return { action, desc = desc }
end

M.source = {
  title = views.title({ view = "containers" }),
  view = "containers",
  grouping = "project",
  only_running = false,
  finder = function(opts)
    return views.items(opts)
  end,
  format = M.format,
  focus = "list",
  auto_close = false,
  jump = { close = false },
  matcher = { sort_empty = false, fuzzy = false, keep_parents = true },
  sort = { fields = {} },
  toggles = { only_running = "running" },
  confirm = "compose_toggle",
  actions = actions,
  on_show = function(picker)
    docker.invalidate()
    docker.load({ "stats" }, function(changed)
      if changed then
        actions.refresh(picker)
      end
    end)
    docker.load_services(function() actions.refresh(picker) end)
    watch(picker)
  end,
  on_close = function()
    if timer then
      timer:stop()
    end
  end,
  win = {
    list = {
      keys = {
        ["l"] = key("compose_toggle", "Open / logs"),
        ["h"] = key("compose_close", "Close node"),
        ["Z"] = key("compose_close_all", "Close all"),
        ["<Tab>"] = key("compose_view_next", "Next view"),
        ["<S-Tab>"] = key("compose_view_prev", "Previous view"),
        ["1"] = key("compose_view_1", "Containers"),
        ["2"] = key("compose_view_2", "Images"),
        ["3"] = key("compose_view_3", "Volumes"),
        ["4"] = key("compose_view_4", "Networks"),
        ["g"] = key("compose_group", "Group by project/state/network/image"),
        ["t"] = key("compose_only_running", "Only running"),
        ["s"] = key("compose_start_stop", "Start / stop"),
        ["r"] = key("compose_restart", "Restart"),
        ["p"] = key("compose_pause", "Pause / resume"),
        ["u"] = key("compose_up", "Compose up"),
        ["d"] = key("compose_delete", "Delete / compose down"),
        ["D"] = key("compose_down_volumes", "Compose down with volumes"),
        ["C"] = key("compose_prune", "Prune this view"),
        ["P"] = key("compose_pull", "Pull"),
        ["L"] = key("compose_logs", "Logs (buffer)"),
        ["x"] = key("compose_shell", "Shell"),
        ["o"] = key("compose_open_port", "Open port in browser"),
        ["e"] = key("compose_edit", "Edit compose file"),
        ["i"] = key("compose_inspect", "Inspect (JSON)"),
        ["K"] = key("compose_details", "Details"),
        ["y"] = key("compose_yank", "Copy ID"),
        ["R"] = key("compose_refresh", "Refresh"),
      },
    },
  },
}

---@param opts? {view?: string, grouping?: string}
function M.open(opts)
  opts = opts or {}
  opts.title = views.title({ view = opts.view or "containers", grouping = opts.grouping })
  Snacks.picker.pick("compose", opts)
end

return M
