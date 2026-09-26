-- Docker logs in an editor buffer instead of a terminal: searchable, yankable,
-- and following new output while the cursor is on the last line (like
-- `tail -f`; move up to stop following, G to resume). One buffer per
-- container/service/project, reused when opened again.
local docker = require("util.compose.docker")

local M = {}

M.icon = "" -- nf-oct-log
M.tail = 500
M.max_lines = 20000

---@type table<string, integer> log key -> buffer
M.buffers = {}

-- drops colour codes; a progress bar redrawn with \r keeps only its final
-- state, as a terminal would show it
local function strip(line)
  line = line:gsub("\27%[[%d;?]*[%a]", ""):gsub("\r+$", "")
  return line:match("[^\r]*$")
end

---@param buf integer
---@param lines string[]
local function append(buf, lines)
  if not vim.api.nvim_buf_is_valid(buf) or #lines == 0 then
    return
  end
  -- windows showing the buffer whose cursor is on the last line keep following
  local follow = {}
  local count = vim.api.nvim_buf_line_count(buf)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.api.nvim_win_get_cursor(win)[1] >= count then
      follow[#follow + 1] = win
    end
  end
  local empty = count == 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, empty and 0 or -1, -1, false, lines)
  count = vim.api.nvim_buf_line_count(buf)
  if count > M.max_lines then
    vim.api.nvim_buf_set_lines(buf, 0, count - M.max_lines, false, {})
    count = M.max_lines
  end
  vim.bo[buf].modifiable = false
  for _, win in ipairs(follow) do
    vim.api.nvim_win_set_cursor(win, { count, 0 })
  end
end

-- collects a stream into complete lines and appends them in batches
local function reader(buf)
  local partial, pending, scheduled = "", {}, false
  return function(_, data)
    if not data then
      return
    end
    local chunk = partial .. data
    local last = chunk:match(".*\n()") or 1
    partial = chunk:sub(last)
    for line in chunk:sub(1, last - 1):gmatch("([^\n]*)\n") do
      pending[#pending + 1] = strip(line)
    end
    if not scheduled then
      scheduled = true
      vim.defer_fn(function()
        scheduled = false
        local lines = pending
        pending = {}
        append(buf, lines)
      end, 50)
    end
  end
end

---@param key string e.g. "container:web-1", "service:proj/web"
---@param title string
---@param cmd string[]
---@param win? integer window to show it in (default: current)
function M.open(key, title, cmd, win)
  win = win and vim.api.nvim_win_is_valid(win) and win or vim.api.nvim_get_current_win()
  local buf = M.buffers[key]
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    buf = vim.api.nvim_create_buf(true, true)
    M.buffers[key] = buf
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].swapfile = false
    vim.bo[buf].modifiable = false
    vim.bo[buf].filetype = "log"
    vim.b[buf].turbo_title = M.icon .. " Logs: " .. title
    pcall(vim.api.nvim_buf_set_name, buf, "docker-logs://" .. title)

    local on_output = reader(buf)
    local ok, job = pcall(vim.system, cmd, { stdout = on_output, stderr = on_output }, vim.schedule_wrap(function(res)
      if vim.api.nvim_buf_is_valid(buf) and res.signal == 0 then
        append(buf, { "", ("── log stream ended (exit %d) ──"):format(res.code) })
      end
    end))
    if not ok then
      vim.notify("docker logs failed: " .. tostring(job), vim.log.levels.ERROR)
    end

    local function close()
      if ok and not job:is_closing() then
        job:kill("sigterm")
      end
      if M.buffers[key] == buf then
        M.buffers[key] = nil
      end
    end
    vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, { buffer = buf, once = true, callback = close })
    vim.keymap.set("n", "q", function() Snacks.bufdelete({ buf = buf, wipe = true }) end, { buffer = buf, desc = "Close logs" })
  end
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
  return buf
end

function M.is_open(key)
  local buf = M.buffers[key]
  return buf ~= nil and vim.api.nvim_buf_is_valid(buf)
end

-- log key, title and command for an explorer item (container, service or
-- project); services and projects need `docker compose`
function M.target(item)
  local base = { "--follow", "--tail", tostring(M.tail) }
  if item.kind == "container" then
    local c = item.container
    local cmd = vim.list_extend({ "docker", "logs" }, base)
    table.insert(cmd, c.id)
    return "container:" .. c.name, c.name, cmd
  end
  if (item.kind == "service" or item.kind == "project") and docker.has_compose() then
    local args = vim.list_extend({ "logs", "--no-color" }, base)
    local key, title = "project:" .. item.project.name, item.project.name
    if item.kind == "service" then
      table.insert(args, item.service)
      key, title = ("service:%s/%s"):format(item.project.name, item.service), item.project.name .. "/" .. item.service
    end
    return key, title, docker.compose_cmd(item.project, args)
  end
end

-- a picker of every compose service and container, opening the chosen log
function M.pick()
  docker.load({ "ps" })
  local items = {}
  for _, p in ipairs(docker.state.projects) do
    for _, service in ipairs(p.services) do
      local list = vim.tbl_filter(function(c) return c.service == service end, p.containers)
      if p.name ~= docker.standalone and #list > 0 then
        local running = #vim.tbl_filter(function(c) return c.state == "running" end, list)
        if #list > 1 and docker.has_compose() then
          items[#items + 1] = {
            kind = "service", project = p, service = service, containers = list,
            text = p.name .. "/" .. service, running = running, total = #list,
          }
        end
      end
      for _, c in ipairs(list) do
        items[#items + 1] = {
          kind = "container", container = c,
          text = p.name == docker.standalone and c.name or (p.name .. "/" .. (#list > 1 and ("%s-%d"):format(service, c.number) or service)),
          running = c.state == "running" and 1 or 0, total = 1,
        }
      end
    end
  end
  if #items == 0 then
    return vim.notify("No containers", vim.log.levels.WARN)
  end
  Snacks.picker({
    title = M.icon .. " Docker Logs",
    items = items,
    layout = { preset = "select" },
    format = function(item)
      local hl = item.running == item.total and "SnacksPickerDockerRunning"
        or item.running > 0 and "SnacksPickerDockerPaused" or "SnacksPickerDockerExited"
      local ret = { { M.icon .. " ", "SnacksPickerIcon" }, { "● ", hl }, { item.text } }
      if item.kind == "service" then
        ret[#ret + 1] = { ("  (%d replicas)"):format(item.total), "SnacksPickerTotals" }
      end
      return ret
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        local key, title, cmd = M.target(item)
        M.open(key, title, cmd)
      end
    end,
  })
end

return M
