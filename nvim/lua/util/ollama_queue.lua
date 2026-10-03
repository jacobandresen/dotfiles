-- Serialize local Ollama inference inside Neovim. Deliberate requests wait in
-- FIFO order; ghost-text requests are discarded when the queue is occupied.
local M = {}
local pending = {}
local active
local sequence = 0

local function finish(item, status)
  if item.finished then return end
  item.finished = true
  item.status = status or "success"
  if active == item then active = nil end
  vim.schedule(function()
    M.drain()
  end)
end

function M.drain()
  if active then return end
  while #pending > 0 do
    local item = table.remove(pending, 1)
    if not item.cancelled then
      active = item
      item.status = "running"
      local ok, err = pcall(item.start, function(status) finish(item, status) end, item)
      if not ok then
        finish(item, "error")
        vim.notify("Ollama request could not start: " .. tostring(err), vim.log.levels.ERROR)
      end
      return
    end
  end
end

function M.is_busy()
  return active ~= nil or #pending > 0
end

function M.submit(start, opts)
  opts = opts or {}
  if opts.drop_if_busy and M.is_busy() then
    if opts.on_drop then opts.on_drop() end
    return nil
  end
  sequence = sequence + 1
  local item = { id = sequence, start = start, status = "pending" }
  pending[#pending + 1] = item
  M.drain()
  return item
end

local function local_ollama(adapter)
  local url = adapter and adapter.url or ""
  if url:sub(1, 6) == "${url}" then
    local resolve = adapter.env and adapter.env.url
    if type(resolve) == "function" then
      local ok, host = pcall(resolve, adapter)
      if ok and type(host) == "string" then
        url = host .. url:sub(7)
      end
    end
  end
  if url:match("^[%w.-]+:11434/") then url = "http://" .. url end
  return url:match("^https?://localhost:11434/") ~= nil
    or url:match("^https?://127%.0%.0%.1:11434/") ~= nil
    or url:match("^https?://%[::1%]:11434/") ~= nil
end

function M.setup_codecompanion()
  local Client = require("codecompanion.http")
  if Client._ollama_queue_installed then return end
  Client._ollama_queue_installed = true
  local new = Client.new
  Client.new = function(args)
    local client = new(args)
    local send = client.send
    client.send = function(self, payload, opts)
      if not local_ollama(self.adapter) then return send(self, payload, opts) end
      opts = opts or {}
      local original_done, original_error = opts.on_done, opts.on_error
      local proxy = { id = "ollama-queued-" .. tostring(sequence + 1), state = "pending" }
      local ticket
      local function settle(state)
        if proxy.state == "success" or proxy.state == "error" or proxy.state == "cancelled" then return end
        proxy.state = state
        if ticket then
          finish(ticket, state)
        elseif proxy._finish then
          proxy._finish(state)
        end
      end
      ticket = M.submit(function(done)
        proxy.state = "pending"
        local wrapped = vim.tbl_extend("force", {}, opts, {
          on_done = function(...)
            settle("success")
            if original_done then original_done(...) end
          end,
          on_error = function(...)
            settle("error")
            if original_error then original_error(...) end
          end,
        })
        proxy._finish = done
        local ok, handle = pcall(send, self, payload, wrapped)
        if not ok then
          settle("error")
          if original_error then original_error({ message = tostring(handle) }) end
          return
        end
        proxy.inner = handle
        if proxy.state == "pending" then proxy.state = "running" end
      end)
      proxy.cancel = function()
        if proxy.state == "pending" then
          proxy.state = "cancelled"
          if ticket then
            ticket.cancelled = true
            for i, item in ipairs(pending) do
              if item == ticket then table.remove(pending, i); break end
            end
          end
          return true
        end
        if proxy.inner and proxy.inner.cancel then
          local ok, cancelled = pcall(proxy.inner.cancel)
          settle("cancelled")
          return ok and cancelled ~= false
        end
        return false
      end
      proxy.status = function() return proxy.state end
      return proxy
    end
    return client
  end
end

function M.setup_minuet()
  local provider = require("minuet.backends.openai_compatible")
  if provider._ollama_queue_installed then return end
  provider._ollama_queue_installed = true
  local complete = provider.complete
  provider.complete = function(context, callback)
    local config = require("minuet").config
    local options = config.provider_options.openai_compatible or {}
    if not local_ollama({ url = options.end_point }) then return complete(context, callback) end
    M.submit(function(done)
      complete(context, function(result)
        done("success")
        callback(result)
      end)
    end, {
      drop_if_busy = true,
      on_drop = function() callback() end,
    })
  end
end

return M
