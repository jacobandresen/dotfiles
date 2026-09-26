-- Docker data for the compose explorer: runs the docker CLI and parses its
-- output into M.state. Raw outputs are cached so the poller can tell when
-- anything changed. Compose grouping comes from the labels compose puts on
-- containers, networks and volumes; the `docker compose` plugin is only
-- needed for compose commands and for services that have no container yet.
local M = {}

local sep = "\t"
M.standalone = "(no project)"
local compose_files = { "compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml" }

local function label(name)
  return ('{{.Label "%s"}}'):format(name)
end

M.cmds = {
  ps = {
    "docker", "ps", "--all", "--no-trunc", "--format",
    table.concat({
      "{{.ID}}", "{{.Names}}", "{{.State}}", "{{.Status}}", "{{.Image}}", "{{.Ports}}",
      "{{.Networks}}", "{{.Mounts}}", "{{.RunningFor}}",
      label("com.docker.compose.project"),
      label("com.docker.compose.service"),
      label("com.docker.compose.container-number"),
      label("com.docker.compose.project.working_dir"),
      label("com.docker.compose.project.config_files"),
    }, sep),
  },
  networks = {
    "docker", "network", "ls", "--format",
    table.concat({ "{{.ID}}", "{{.Name}}", "{{.Driver}}", "{{.Scope}}", label("com.docker.compose.project"),
      label("com.docker.compose.network") }, sep),
  },
  -- images and volumes, with sizes and usage counts
  df = { "docker", "system", "df", "--verbose", "--format", "json" },
  stats = { "docker", "stats", "--no-stream", "--format", "{{.ID}}\t{{.CPUPerc}}\t{{.MemUsage}}" },
}

---@class compose.Container
---@field id string short id
---@field name string
---@field state string running|exited|paused|restarting|created|dead
---@field status string
---@field image string
---@field ports string
---@field networks string[]
---@field mounts string[]
---@field age string
---@field project string
---@field service string
---@field number integer

---@class compose.Project
---@field name string
---@field wd? string
---@field files? string comma separated
---@field containers compose.Container[]
---@field services string[] service names, in order

M.raw = {} ---@type table<string, string?>
M.state = {
  containers = {}, ---@type compose.Container[]
  projects = {}, ---@type compose.Project[]
  networks = {},
  images = {},
  volumes = {},
  stats = {}, ---@type table<string, {cpu: string, mem: string}>
  services = {}, ---@type table<string, string[]> project -> services from `compose config`
}

local function split(s, pat)
  local ret = {}
  for part in (s or ""):gmatch(pat or "[^,]+") do
    ret[#ret + 1] = vim.trim(part)
  end
  return ret
end

local parse = {}

function parse.ps(out)
  local containers = {}
  for line in out:gmatch("[^\n]+") do
    local f = vim.split(line, sep, { plain = true })
    containers[#containers + 1] = {
      id = f[1]:sub(1, 12), name = f[2], state = f[3], status = f[4], image = f[5], ports = f[6],
      networks = split(f[7]), mounts = split(f[8]), age = f[9],
      project = f[10] ~= "" and f[10] or M.standalone,
      service = f[11] ~= "" and f[11] or f[2], number = tonumber(f[12]) or 1,
      wd = f[13], files = f[14],
    }
  end
  -- containers per service, so replicas get a -N suffix in grouped views
  local replicas = {}
  for _, c in ipairs(containers) do
    local key = c.project .. "/" .. c.service
    replicas[key] = (replicas[key] or 0) + 1
  end
  for _, c in ipairs(containers) do
    c.replicas = replicas[c.project .. "/" .. c.service]
  end
  M.state.containers = containers
end

function parse.networks(out)
  local networks = {}
  for line in out:gmatch("[^\n]+") do
    local f = vim.split(line, sep, { plain = true })
    networks[#networks + 1] = {
      id = f[1], name = f[2], driver = f[3], scope = f[4],
      project = f[5] ~= "" and f[5] or nil, short = f[6] ~= "" and f[6] or f[2],
      system = vim.tbl_contains({ "bridge", "host", "none" }, f[2]),
    }
  end
  M.state.networks = networks
end

function parse.df(out)
  local ok, df = pcall(vim.json.decode, out)
  if not ok or type(df) ~= "table" then
    return
  end
  local images, volumes = {}, {}
  for _, i in ipairs(df.Images or {}) do
    images[#images + 1] = {
      id = i.ID:gsub("^sha256:", ""):sub(1, 12), repo = i.Repository, tag = i.Tag, size = i.Size,
      created = i.CreatedSince, containers = tonumber(i.Containers) or 0,
      dangling = i.Repository == "<none>",
    }
  end
  for _, v in ipairs(df.Volumes or {}) do
    local labels = v.Labels or ""
    volumes[#volumes + 1] = {
      name = v.Name, driver = v.Driver, size = v.Size, links = tonumber(v.Links) or 0,
      mountpoint = v.Mountpoint,
      project = labels:match("com%.docker%.compose%.project=([^,]+)"),
      short = labels:match("com%.docker%.compose%.volume=([^,]+)"),
      anonymous = v.Name:match("^%x+$") and #v.Name == 64 or nil,
    }
  end
  M.state.images, M.state.volumes = images, volumes
end

function parse.stats(out)
  local stats = {}
  for line in out:gmatch("[^\n]+") do
    local f = vim.split(line, sep, { plain = true })
    stats[f[1]:sub(1, 12)] = { cpu = f[2], mem = vim.trim((f[3] or ""):match("^[^/]+") or "") }
  end
  M.state.stats = stats
end

-- containers grouped into compose projects, plus services from `compose
-- config` without a container, plus the root dir's compose file when it has
-- no containers at all yet
local function build_projects()
  local projects, by_name = {}, {}
  local function project(name, wd, files)
    if not by_name[name] then
      by_name[name] = { name = name, wd = wd, files = files, containers = {}, services = {} }
      projects[#projects + 1] = by_name[name]
    end
    return by_name[name]
  end
  for _, c in ipairs(M.state.containers) do
    local p = project(c.project, c.wd, c.files)
    table.insert(p.containers, c)
  end

  local root = LazyVim.root()
  for _, file in ipairs(compose_files) do
    local path = root .. "/" .. file
    if vim.uv.fs_stat(path) then
      local name = vim.fs.basename(root):lower():gsub("[^%w_-]", "")
      local known = by_name[name] or vim.iter(projects):find(function(p) return p.wd == root end)
      if not known then
        project(name, root, path)
      end
      break
    end
  end

  for _, p in ipairs(projects) do
    local seen = {}
    for _, c in ipairs(p.containers) do
      if not seen[c.service] then
        seen[c.service] = true
        table.insert(p.services, c.service)
      end
    end
    for _, s in ipairs(M.state.services[p.name] or {}) do
      if not seen[s] then
        seen[s] = true
        table.insert(p.services, s)
      end
    end
    table.sort(p.services)
    table.sort(p.containers, function(a, b)
      if a.service ~= b.service then
        return a.service < b.service
      end
      return a.number < b.number
    end)
  end
  table.sort(projects, function(a, b)
    if (a.name == M.standalone) ~= (b.name == M.standalone) then
      return b.name == M.standalone
    end
    return a.name < b.name
  end)
  M.state.projects = projects
end

---@param kinds string[] which commands to (re)load
---@param cb? fun(changed: boolean) async when given, else synchronous
function M.load(kinds, cb)
  local pending, changed = #kinds, false
  local function done(kind, res)
    if res.code == 0 and res.stdout ~= M.raw[kind] then
      M.raw[kind] = res.stdout
      parse[kind](res.stdout)
      changed = true
    elseif res.code ~= 0 and not cb then
      vim.notify(("docker %s failed: %s"):format(kind, vim.trim(res.stderr or "")), vim.log.levels.ERROR)
    end
    pending = pending - 1
    if pending == 0 then
      if changed then
        build_projects()
      end
      if cb then
        cb(changed)
      end
    end
  end
  for _, kind in ipairs(kinds) do
    if cb then
      vim.system(M.cmds[kind], { text = true }, vim.schedule_wrap(function(res) done(kind, res) end))
    else
      done(kind, vim.system(M.cmds[kind], { text = true }):wait())
    end
  end
end

-- make sure the given kinds were loaded at least once
function M.ensure(kinds)
  local missing = vim.tbl_filter(function(k) return M.raw[k] == nil end, kinds)
  if #missing > 0 then
    M.load(missing)
  end
end

function M.invalidate()
  M.raw = {}
end

-- `docker compose` plugin ------------------------------------------------------

local has_compose ---@type boolean?

function M.has_compose()
  if has_compose == nil then
    has_compose = vim.system({ "docker", "compose", "version" }):wait().code == 0
  end
  return has_compose
end

---@param p compose.Project
---@param args string[]
---@return string[]?
function M.compose_cmd(p, args)
  if p.name == M.standalone then
    return
  end
  local cmd = { "docker", "compose", "--project-name", p.name }
  if p.wd and p.wd ~= "" then
    vim.list_extend(cmd, { "--project-directory", p.wd })
  end
  for file in (p.files or ""):gmatch("[^,]+") do
    vim.list_extend(cmd, { "--file", file })
  end
  return vim.list_extend(cmd, args)
end

-- services declared in each project's compose files (async)
function M.load_services(cb)
  if not M.has_compose() then
    return
  end
  for _, p in ipairs(M.state.projects) do
    local cmd = p.files and p.files ~= "" and M.compose_cmd(p, { "config", "--services" })
    if cmd then
      vim.system(cmd, { text = true }, vim.schedule_wrap(function(res)
        if res.code == 0 then
          local services = split(res.stdout, "[^\n]+")
          if not vim.deep_equal(services, M.state.services[p.name]) then
            M.state.services[p.name] = services
            build_projects()
            cb()
          end
        end
      end))
    end
  end
end

return M
