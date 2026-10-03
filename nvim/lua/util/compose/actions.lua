-- Actions of the compose explorer. Most work on any node: a container, a
-- service or project (all its containers; through `docker compose` when the
-- plugin is installed, so depends_on order is kept), or a state/network/image
-- group. Images, volumes and networks have their own delete/inspect/shell.
local docker = require("util.compose.docker")
local views = require("util.compose.views")

local M = {}

-- identifies a row across refreshes (a container can be listed under several
-- groups, so its parent is part of the key)
local function key(item)
  local own = item.id or (item.container and item.container.name) or item.text
  return own .. "@" .. (item.parent and key(item.parent) or "")
end

-- re-runs the finder, keeping the cursor on the same row even when rows
-- above it came or went (set_target keeps the index, and loses it anyway
-- with this synchronous finder)
---@param picker snacks.Picker
function M.refresh(picker)
  if picker.closed then
    return
  end
  local current, cursor = picker:current(), picker.list.cursor
  local want = current and key(current)
  picker:find()
  -- find's on_done can fire before the matcher starts, so wait until idle
  local tries = 0
  local function restore()
    if picker.closed then
      return
    end
    tries = tries + 1
    if picker:is_active() and tries < 50 then
      return vim.defer_fn(restore, 10)
    end
    for i = 1, picker.list:count() do
      local item = picker.list:get(i)
      if item and key(item) == want then
        return picker.list:view(i)
      end
    end
    picker.list:view(math.min(cursor, math.max(picker.list:count(), 1)))
  end
  vim.defer_fn(restore, 10)
end

local function notify(msg, level)
  vim.notify(msg, level, { title = "Docker" })
end

---@param picker snacks.Picker
---@param cmd string[]
---@param what string shown in the notifications
local function run(picker, cmd, what, after)
  notify(what .. "...")
  vim.system(cmd, { text = true }, vim.schedule_wrap(function(res)
    if res.code == 0 then
      notify(what .. " done")
    else
      notify(what .. " failed:\n" .. vim.trim(res.stderr ~= "" and res.stderr or res.stdout or ""), vim.log.levels.ERROR)
    end
    docker.invalidate()
    if after then
      after()
    end
    M.refresh(picker)
  end))
end

local function confirm(msg)
  return vim.fn.confirm(msg, "&Yes\n&No", 2) == 1
end

-- a terminal in the lazygit window style (double frame, Alt+X to close)
local function terminal(cmd, title)
  Snacks.terminal(cmd, { win = { style = "lazygit", title = " " .. title .. " " } })
end

local function containers(item)
  return item.kind == "container" and { item.container } or item.containers or {}
end

local function ids(list)
  return vim.tbl_map(function(c) return c.id end, list)
end

-- `docker compose ... <args> [service]` for project and service nodes
local function compose(item, args)
  if not (item.kind == "project" or item.kind == "service") or not docker.has_compose() then
    return
  end
  args = vim.deepcopy(args)
  if item.kind == "service" then
    table.insert(args, item.service)
  end
  return docker.compose_cmd(item.project, args)
end

local function name(item)
  return item.label or item.text
end

local function reload_services(picker)
  return function()
    docker.load_services(function() M.refresh(picker) end)
  end
end

-- tree -------------------------------------------------------------------------

function M.compose_toggle(picker, item)
  if item.dir then
    views.open[item.id] = not item.open
    M.refresh(picker)
  elseif item.kind == "container" then
    M.compose_logs(picker, item)
  else
    M.compose_details(picker, item)
  end
end

function M.compose_close(picker, item)
  local node = (item.dir and item.open) and item or item.parent
  if not node then
    return
  end
  views.open[node.id] = false
  -- put the cursor on the node before its children disappear
  local idx = picker.list.cursor
  while idx > 1 and picker.list:get(idx) ~= node do
    idx = idx - 1
  end
  picker.list:view(idx)
  M.refresh(picker)
end

function M.compose_close_all(picker)
  for i = 1, picker.list:count() do
    local item = picker.list:get(i)
    if item and item.dir and not item.parent then
      views.open[item.id] = false
    end
  end
  picker.list:view(1)
  M.refresh(picker)
end

-- views, grouping, filters -----------------------------------------------------

local function set_view(picker, view)
  picker.opts.view = view
  picker.title = views.title(picker.opts)
  picker.input:set("", "")
  picker.list:view(1)
  picker:update_titles()
  picker:find()
end

function M.compose_view_next(picker)
  local i = vim.fn.index(views.order, picker.opts.view) + 1
  set_view(picker, views.order[i % #views.order + 1])
end

function M.compose_view_prev(picker)
  local i = vim.fn.index(views.order, picker.opts.view) + 1
  set_view(picker, views.order[(i - 2) % #views.order + 1])
end

for i, view in ipairs(views.order) do
  M["compose_view_" .. i] = function(picker) set_view(picker, view) end
end

function M.compose_group(picker)
  if picker.opts.view ~= "containers" then
    return set_view(picker, "containers")
  end
  local i = vim.fn.index(views.groupings, picker.opts.grouping or "project") + 1
  picker.opts.grouping = views.groupings[i % #views.groupings + 1]
  picker.title = views.title(picker.opts)
  picker:update_titles()
  picker.list:view(1)
  picker:find()
end

function M.compose_only_running(picker)
  picker.opts.only_running = not picker.opts.only_running
  picker:update_titles()
  M.refresh(picker)
end

function M.compose_refresh(picker)
  docker.invalidate()
  reload_services(picker)()
  M.refresh(picker)
end

-- container lifecycle ----------------------------------------------------------

-- stops if anything is running, else starts; `up` creates what doesn't exist
function M.compose_start_stop(picker, item)
  if item.kind == "image" or item.kind == "volume" or item.kind == "network" then
    return
  end
  local list = containers(item)
  local up = vim.iter(list):any(function(c) return c.state == "running" or c.state == "restarting" end)
  local cmd = compose(item, { up and "stop" or "start" })
  if #list == 0 or (not up and #list < (item.kind == "project" and #item.project.services or #list)) then
    return M.compose_up(picker, item)
  end
  run(picker, cmd or vim.list_extend({ "docker", up and "stop" or "start" }, ids(list)),
    (up and "Stopping " or "Starting ") .. name(item))
end

function M.compose_restart(picker, item)
  local list = containers(item)
  if #list > 0 then
    run(picker, compose(item, { "restart" }) or vim.list_extend({ "docker", "restart" }, ids(list)), "Restarting " .. name(item))
  end
end

function M.compose_pause(picker, item)
  local list = containers(item)
  local paused = vim.tbl_filter(function(c) return c.state == "paused" end, list)
  local running = vim.tbl_filter(function(c) return c.state == "running" end, list)
  if #paused > 0 then
    run(picker, vim.list_extend({ "docker", "unpause" }, ids(paused)), "Resuming " .. name(item))
  elseif #running > 0 then
    run(picker, vim.list_extend({ "docker", "pause" }, ids(running)), "Pausing " .. name(item))
  end
end

function M.compose_up(picker, item)
  if item.kind == "container" then
    item = item.parent and item.parent.kind == "service" and item.parent or item
  end
  if not docker.has_compose() then
    return notify("`docker compose` is not installed (make deps-compose)", vim.log.levels.WARN)
  end
  local cmd = compose(item, { "up", "--detach" })
  if not cmd then
    return notify("Not a compose project or service", vim.log.levels.WARN)
  end
  run(picker, cmd, "Compose up " .. name(item), reload_services(picker))
end

function M.compose_pull(picker, item)
  if item.kind == "image" then
    if item.image.dangling then
      return notify("Dangling images can't be pulled", vim.log.levels.WARN)
    end
    return run(picker, { "docker", "pull", item.image.name }, "Pulling " .. item.image.name)
  end
  local cmd = compose(item, { "pull" })
  if cmd then
    run(picker, cmd, "Pulling " .. name(item))
  elseif item.kind == "container" then
    run(picker, { "docker", "pull", item.container.image }, "Pulling " .. item.container.image)
  end
end

-- delete: container/service remove, project `compose down`, image/volume/network rm
function M.compose_delete(picker, item)
  local kind = item.kind
  if kind == "project" then
    local cmd = compose(item, { "down", "--remove-orphans" })
    if not cmd then
      return notify("`docker compose` is needed for down (or not a compose project)", vim.log.levels.WARN)
    end
    if confirm(("Compose down %s? (stops and removes its containers and networks)"):format(name(item))) then
      run(picker, cmd, "Compose down " .. name(item), reload_services(picker))
    end
  elseif kind == "container" or kind == "service" then
    local list = containers(item)
    if #list > 0 and confirm(("Remove %s (%d container%s)?"):format(name(item), #list, #list == 1 and "" or "s")) then
      run(picker, compose(item, { "rm", "--stop", "--force" }) or vim.list_extend({ "docker", "rm", "--force" }, ids(list)),
        "Removing " .. name(item))
    end
  elseif kind == "image" and confirm(("Delete image %s?"):format(item.image.name)) then
    run(picker, { "docker", "image", "rm", item.image.dangling and item.image.id or item.image.name }, "Deleting " .. item.image.name)
  elseif kind == "volume" then
    if item.used then
      return notify(("%s is in use by %d container(s)"):format(item.label, #item.containers), vim.log.levels.WARN)
    end
    if confirm(("Delete volume %s and its data?"):format(item.volume.name)) then
      run(picker, { "docker", "volume", "rm", item.volume.name }, "Deleting " .. item.label)
    end
  elseif kind == "network" then
    if item.network.system then
      return notify("Built-in networks can't be removed", vim.log.levels.WARN)
    end
    if confirm(("Delete network %s?"):format(item.network.name)) then
      run(picker, { "docker", "network", "rm", item.network.name }, "Deleting " .. item.label)
    end
  end
end

-- compose down --volumes: Docker Desktop's "delete stack" with its data
function M.compose_down_volumes(picker, item)
  local cmd = item.kind == "project" and compose(item, { "down", "--volumes", "--remove-orphans" })
  if cmd and confirm(("Compose down %s and DELETE its volumes?"):format(name(item))) then
    run(picker, cmd, "Compose down -v " .. name(item), reload_services(picker))
  end
end

local prune = {
  containers = { { "docker", "container", "prune", "--force" }, "Remove all stopped containers?" },
  images = { { "docker", "image", "prune", "--force" }, "Remove all dangling images?" },
  volumes = { { "docker", "volume", "prune", "--force" }, "Remove all unused anonymous volumes?" },
  networks = { { "docker", "network", "prune", "--force" }, "Remove all unused networks?" },
}

function M.compose_prune(picker)
  local p = prune[picker.opts.view]
  if confirm(p[2]) then
    run(picker, p[1], "Pruning " .. picker.opts.view)
  end
end

-- terminals ------------------------------------------------------------------------

-- logs in an editor buffer next to the explorer (util/compose/logs.lua)
function M.compose_logs(picker, item)
  local logs = require("util.compose.logs")
  local key, title, cmd = logs.target(item)
  if not key then
    local list = containers(item)
    if #list ~= 1 then
      return notify("Logs of several containers need `docker compose`", vim.log.levels.WARN)
    end
    key, title, cmd = logs.target({ kind = "container", container = list[1] })
  end
  logs.open(key, title, cmd, picker.main)
  vim.api.nvim_set_current_win(picker.main)
  M.refresh(picker) -- shows the log icon on the row
end

-- shell in a container, in a throwaway container of an image, or in a volume
function M.compose_shell(_, item)
  local sh = "command -v bash >/dev/null && exec bash || exec sh"
  if item.kind == "container" then
    local c = item.container
    if c.state ~= "running" then
      return notify(c.name .. " is not running", vim.log.levels.WARN)
    end
    terminal({ "docker", "exec", "-it", c.id, "sh", "-c", sh }, "Shell: " .. c.name)
  elseif item.kind == "image" then
    local image = item.image.dangling and item.image.id or item.image.name
    terminal({ "docker", "run", "--rm", "-it", "--entrypoint", "sh", image, "-c", sh }, "Run: " .. item.label)
  elseif item.kind == "volume" then
    terminal({ "docker", "run", "--rm", "-it", "-v", item.volume.name .. ":/volume", "-w", "/volume", "alpine", "sh" },
      "Volume: " .. item.label)
  end
end

-- browser / editor -----------------------------------------------------------------

local function published_ports(list)
  local ports, seen = {}, {}
  for _, c in ipairs(list) do
    for host, port in c.ports:gmatch("([%d%.:%[%]]+):(%d+)%->%d+/tcp") do
      if not seen[port] then
        seen[port] = true
        ports[#ports + 1] = { port = port, label = ("%s  localhost:%s  (%s)"):format(c.name, port, host) }
      end
    end
  end
  return ports
end

-- Docker Desktop's port link: open http://localhost:<port> in the browser
function M.compose_open_port(_, item)
  local ports = published_ports(containers(item))
  local function open(p)
    if p then
      vim.ui.open("http://localhost:" .. p.port)
    end
  end
  if #ports == 0 then
    return notify("No published TCP ports", vim.log.levels.WARN)
  elseif #ports == 1 then
    return open(ports[1])
  end
  vim.ui.select(ports, { prompt = "Open port", format_item = function(p) return p.label end }, open)
end

function M.compose_edit(picker, item)
  local p = item.project or (item.container and vim.iter(docker.state.projects):find(function(x)
    return x.name == item.container.project
  end))
  local file = p and (p.files or ""):match("[^,]+")
  if not file or file == "" then
    return notify("No compose file", vim.log.levels.WARN)
  end
  picker:action("close")
  vim.cmd.edit(vim.fn.fnameescape(file))
end

-- inspect / details ----------------------------------------------------------------

local inspect_cmd = {
  container = function(item) return { "docker", "inspect", item.container.id } end,
  image = function(item) return { "docker", "image", "inspect", item.image.id } end,
  volume = function(item) return { "docker", "volume", "inspect", item.volume.name } end,
  network = function(item) return { "docker", "network", "inspect", item.network.id } end,
}

function M.compose_inspect(_, item)
  local cmd = inspect_cmd[item.kind] and inspect_cmd[item.kind](item)
    or (#containers(item) > 0 and vim.list_extend({ "docker", "inspect" }, ids(containers(item))))
  if not cmd then
    return
  end
  local origin = vim.api.nvim_get_current_win()
  notify("Loading Docker inspect...")
  vim.system(cmd, { text = true, timeout = 10000 }, vim.schedule_wrap(function(res)
    if res.code ~= 0 then
      return notify(vim.trim(res.stderr or ""), vim.log.levels.ERROR)
    end
    if not vim.api.nvim_win_is_valid(origin) then return end
    vim.api.nvim_win_call(origin, function()
      vim.cmd("wincmd l | enew")
      vim.bo.buftype, vim.bo.bufhidden, vim.bo.filetype = "nofile", "wipe", "json"
      vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(vim.trim(res.stdout), "\n"))
      pcall(vim.api.nvim_buf_set_name, 0, ("docker-inspect://%s/%s"):format(item.kind, item.text))
    end)
  end))
end

local function field(lines, key, value)
  if value and value ~= "" then
    local first = true
    for _, v in ipairs(type(value) == "table" and value or { value }) do
      table.insert(lines, ("%-9s %s"):format(first and key or "", v))
      first = false
    end
  end
end

local details = {}

function details.container(item)
  local c, lines = item.container, {}
  local stats = docker.state.stats[c.id]
  field(lines, "Name", c.name)
  field(lines, "ID", c.id)
  field(lines, "Image", c.image)
  field(lines, "Status", c.status)
  field(lines, "Created", c.age)
  if stats then
    field(lines, "CPU", stats.cpu)
    field(lines, "Memory", stats.mem)
  end
  if c.project ~= docker.standalone then
    field(lines, "Project", c.project)
    field(lines, "Service", c.service)
  end
  field(lines, "Ports", vim.tbl_map(function(p) return vim.trim(p) end, vim.split(c.ports, ",", { trimempty = true })))
  field(lines, "Networks", c.networks)
  field(lines, "Mounts", c.mounts)
  return lines
end

function details.project(item)
  local lines, p = {}, item.project
  field(lines, "Project", p.name)
  field(lines, "Running", ("%d of %d containers"):format(item.running, item.total))
  field(lines, "Services", p.services)
  field(lines, "Directory", p.wd)
  field(lines, "Files", vim.split(p.files or "", ",", { trimempty = true }))
  return lines
end

function details.service(item)
  local lines = {}
  field(lines, "Service", item.service)
  field(lines, "Project", item.project.name)
  field(lines, "Running", ("%d of %d containers"):format(item.running, item.total))
  field(lines, "Replicas", vim.tbl_map(function(c) return c.name .. "  " .. c.status end, item.containers))
  return lines
end

function details.group(item)
  local lines = {}
  field(lines, "Group", item.label)
  if item.containers then
    field(lines, "Running", ("%d of %d containers"):format(item.running, item.total))
  end
  return lines
end

function details.image(item)
  local i, lines = item.image, {}
  field(lines, "Image", i.name)
  field(lines, "ID", i.id)
  field(lines, "Size", i.size)
  field(lines, "Created", i.created)
  field(lines, "In use", item.used and "yes" or "no")
  return lines
end

local function users(item)
  return vim.tbl_map(function(c) return c.name .. "  (" .. c.state .. ")" end, item.containers)
end

function details.volume(item)
  local v, lines = item.volume, {}
  field(lines, "Volume", v.name)
  field(lines, "Driver", v.driver)
  field(lines, "Size", v.size)
  field(lines, "Path", v.mountpoint)
  field(lines, "Used by", #item.containers > 0 and users(item) or "(unused)")
  return lines
end

function details.network(item)
  local n, lines = item.network, {}
  field(lines, "Network", n.name)
  field(lines, "ID", n.id)
  field(lines, "Driver", n.driver)
  field(lines, "Scope", n.scope)
  field(lines, "Used by", #item.containers > 0 and users(item) or "(unused)")
  return lines
end

-- a Turbo Vision dialog with the node's details (Docker Desktop's detail page)
function M.compose_details(_, item)
  local lines = details[item.kind] and details[item.kind](item)
  if not lines or #lines == 0 then
    return
  end
  lines = vim.tbl_map(function(l) return " " .. l .. " " end, lines)
  local width = math.min(vim.o.columns - 4, math.max(30, unpack(vim.tbl_map(vim.api.nvim_strwidth, lines))))
  Snacks.win({
    text = lines,
    width = width,
    height = #lines,
    border = "double",
    title = " " .. name(item) .. " ",
    title_pos = "center",
    footer = " Esc Close ",
    footer_pos = "center",
    backdrop = false,
    wo = {
      winhighlight = "NormalFloat:TurboDialog,FloatBorder:TurboDialogFrame,FloatTitle:TurboDialogTitle,FloatFooter:TurboDialogFrame",
      cursorline = false,
      wrap = false,
    },
    bo = { modifiable = false },
    keys = { q = "close", ["<Esc>"] = "close", K = "close" },
  })
end

function M.compose_yank(_, item)
  local value = item.container and item.container.id or item.image and item.image.id
    or item.volume and item.volume.name or item.network and item.network.id or item.text
  vim.fn.setreg("+", value)
  notify("Copied " .. value)
end

return M
