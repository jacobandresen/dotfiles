-- The explorer's views, Docker Desktop's sections: Containers (grouped by
-- compose project, state, network or image), Images, Volumes and Networks.
-- Each builds a flat list of tree items (parent/last as Snacks expects).
local docker = require("util.compose.docker")

local M = {}

M.order = { "containers", "images", "volumes", "networks" }
M.titles = { containers = "Containers", images = "Images", volumes = "Volumes", networks = "Networks" }
M.groupings = { "project", "state", "network", "image" }

-- docker commands each view reads (stats only matter for containers)
M.needs = {
  containers = { "ps" },
  images = { "ps", "df" },
  volumes = { "ps", "df" },
  networks = { "ps", "networks" },
}

function M.title(opts)
  local title = M.titles[opts.view]
  return opts.view == "containers" and ("%s by %s"):format(title, opts.grouping or "project") or title
end

M.open = {} ---@type table<string, boolean> node id -> open, overriding the default

---@class compose.Builder
---@field items table[]
---@field opts table picker opts
local Builder = {}
Builder.__index = Builder

-- adds a node; children are only added while it is open
function Builder:node(item, parent, default_open)
  item.parent = parent
  if item.id then
    local open = M.open[item.id]
    if open == nil then
      open = default_open ~= false
    end
    item.open = open
    item.dir = true
  end
  table.insert(self.items, item)
  return item
end

function Builder:visible(parent)
  return not parent or (parent.open and self:visible(parent.parent))
end

local function running(containers)
  return #vim.tbl_filter(function(c) return c.state == "running" end, containers)
end

local function filter(opts, containers)
  if not opts.only_running then
    return containers
  end
  return vim.tbl_filter(function(c) return c.state == "running" or c.state == "restarting" end, containers)
end

-- containers -------------------------------------------------------------------

---@param b compose.Builder
---@param c compose.Container
function Builder:container(c, parent, label)
  if self:visible(parent) then
    self:node({ kind = "container", container = c, label = label or c.name, text = c.name .. " " .. c.service }, parent)
  end
end

local by = {}

function by.project(b)
  for _, p in ipairs(docker.state.projects) do
    local containers = filter(b.opts, p.containers)
    if #containers > 0 or (not b.opts.only_running and p.name ~= docker.standalone) then
      local pnode = b:node({
        kind = "project", project = p, id = "project:" .. p.name, text = p.name, label = p.name,
        total = #p.containers, running = running(p.containers), containers = p.containers,
      })
      if p.name == docker.standalone then
        for _, c in ipairs(containers) do
          b:container(c, pnode)
        end
      else
        for _, service in ipairs(p.services) do
          local list = vim.tbl_filter(function(c) return c.service == service end, containers)
          local all = vim.tbl_filter(function(c) return c.service == service end, p.containers)
          if #list == 1 and #all == 1 then
            b:container(list[1], pnode, service)
          elseif #list > 0 or (#all == 0 and not b.opts.only_running) then
            local snode = b:visible(pnode) and b:node({
              kind = "service", project = p, service = service, id = ("service:%s/%s"):format(p.name, service),
              text = service, label = service, containers = all, total = #all, running = running(all),
            }, pnode)
            for _, c in ipairs(snode and list or {}) do
              b:container(c, snode, ("%s-%d"):format(service, c.number))
            end
          end
        end
      end
    end
  end
end

local state_groups = {
  { "Running", { running = true } },
  { "Restarting", { restarting = true } },
  { "Paused", { paused = true } },
  { "Stopped", { exited = true, dead = true } },
  { "Created", { created = true } },
}

local function qualified(c)
  if c.project == docker.standalone then
    return c.name
  end
  local service = c.replicas > 1 and ("%s-%d"):format(c.service, c.number) or c.service
  return c.project .. "/" .. service
end

local function sorted(list)
  table.sort(list, function(a, b) return qualified(a) < qualified(b) end)
  return list
end

-- groups containers by key(c) -> list of names, in sorted order
function Builder:grouped(kind, keys)
  local groups, names = {}, {}
  for _, c in ipairs(filter(self.opts, docker.state.containers)) do
    for _, key in ipairs(keys(c)) do
      if not groups[key] then
        groups[key] = {}
        names[#names + 1] = key
      end
      table.insert(groups[key], c)
    end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local list = sorted(groups[name])
    local g = self:node({
      kind = "group", id = kind .. ":" .. name, text = name, label = name,
      containers = list, total = #list, running = running(list),
    })
    for _, c in ipairs(list) do
      self:container(c, g, qualified(c))
    end
  end
end

function by.state(b)
  for _, sg in ipairs(state_groups) do
    local list = sorted(vim.tbl_filter(function(c) return sg[2][c.state] end, filter(b.opts, docker.state.containers)))
    if #list > 0 then
      local g = b:node({
        kind = "group", id = "state:" .. sg[1], text = sg[1], label = sg[1],
        containers = list, total = #list, running = running(list),
      })
      for _, c in ipairs(list) do
        b:container(c, g, qualified(c))
      end
    end
  end
end

function by.network(b)
  b:grouped("network", function(c) return #c.networks > 0 and c.networks or { "(none)" } end)
end

function by.image(b)
  b:grouped("image", function(c) return { c.image } end)
end

local build = {}

function build.containers(b)
  by[b.opts.grouping or "project"](b)
end

-- images -----------------------------------------------------------------------

function build.images(b)
  local used = {}
  for _, c in ipairs(docker.state.containers) do
    used[c.image] = true
  end
  local groups = { { "In use", {} }, { "Unused", {} }, { "Dangling", {} } }
  for _, i in ipairs(docker.state.images) do
    i.name = i.dangling and ("<none> " .. i.id) or (i.repo .. ":" .. i.tag)
    local in_use = i.containers > 0 or used[i.name] or used[i.id] or (i.tag == "latest" and used[i.repo])
    table.insert((i.dangling and groups[3] or in_use and groups[1] or groups[2])[2], i)
  end
  for _, g in ipairs(groups) do
    if #g[2] > 0 then
      table.sort(g[2], function(x, y) return x.name < y.name end)
      local gnode = b:node({ kind = "group", id = "images:" .. g[1], text = g[1], label = g[1], count = #g[2] },
        nil, g[1] ~= "Dangling")
      for _, i in ipairs(g[2]) do
        if b:visible(gnode) then
          -- the sidebar is narrow: drop the registry host, keep repo:tag
          local short = i.dangling and i.name or i.name:gsub("^[%w.-]+%.[%w.-]+[:%d]*/", "")
          b:node({ kind = "image", image = i, label = short, text = i.name, used = g[1] == "In use" }, gnode)
        end
      end
    end
  end
end

-- volumes and networks: grouped by compose project, containers underneath -------

local function users(field, name)
  return vim.tbl_filter(function(c) return vim.tbl_contains(c[field], name) end, docker.state.containers)
end

---@param list table[] volumes or networks
---@param kind "volume"|"network"
---@param field "mounts"|"networks" the container field that references them
function Builder:by_project(list, kind, field, group_of)
  local groups, names = {}, {}
  for _, x in ipairs(list) do
    local g = group_of(x)
    if not groups[g] then
      groups[g] = {}
      names[#names + 1] = g
    end
    table.insert(groups[g], x)
  end
  table.sort(names, function(a, b)
    if a:sub(1, 1) == "(" or b:sub(1, 1) == "(" then
      return a:sub(1, 1) ~= "(" -- (no project)/(system) last
    end
    return a < b
  end)
  for _, g in ipairs(names) do
    table.sort(groups[g], function(x, y) return x.name < y.name end)
    local gnode = self:node({ kind = "group", id = kind .. "s:" .. g, text = g, label = g, count = #groups[g] })
    for _, x in ipairs(groups[g]) do
      if self:visible(gnode) then
        local cs = sorted(users(field, x.name))
        local label = x.short or (x.anonymous and x.name:sub(1, 12)) or x.name
        local node = self:node({
          kind = kind, [kind] = x, id = kind .. ":" .. x.name, label = label, text = x.name,
          containers = cs, used = #cs > 0,
        }, gnode, false)
        for _, c in ipairs(cs) do
          self:container(c, node, qualified(c))
        end
      end
    end
  end
end

function build.volumes(b)
  b:by_project(docker.state.volumes, "volume", "mounts", function(v)
    return v.project or (v.anonymous and "(anonymous)") or docker.standalone
  end)
end

function build.networks(b)
  b:by_project(docker.state.networks, "network", "networks", function(n)
    return n.project or (n.system and "(system)") or docker.standalone
  end)
end

-- marks the last child of every parent, for the tree lines
local function mark_last(items)
  local last = {}
  for _, item in ipairs(items) do
    last[item.parent or "root"] = item
  end
  for _, item in pairs(last) do
    item.last = true
  end
end

---@param opts table picker opts (view, grouping, only_running)
function M.items(opts)
  local b = setmetatable({ items = {}, opts = opts }, Builder)
  build[opts.view](b)
  mark_last(b.items)
  return b.items
end

return M
