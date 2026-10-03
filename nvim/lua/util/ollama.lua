-- Shared asynchronously refreshed model cache for chat and ghost text.
local M = {}
local model, busy, last_refresh, warned = nil, false, 0, false

function M.cached_model()
  return model or "unknown"
end

local function publish(name)
  model = name
  if name then warned = false end
  local minuet = package.loaded["minuet"]
  if minuet and minuet.config then
    minuet.config.provider_options.openai_compatible.model = M.cached_model()
  end
end

function M.refresh()
  if busy then return end
  busy = true
  last_refresh = vim.uv.now()
  local function query(endpoint, callback)
    vim.system({ "curl", "-fsS", "--max-time", "2", "http://localhost:11434/api/" .. endpoint },
      { text = true }, vim.schedule_wrap(function(result)
        local ok, decoded = pcall(vim.json.decode, result.stdout or "")
        callback(result.code == 0 and ok and type(decoded) == "table" and decoded.models or {})
      end))
  end
  query("ps", function(loaded)
    if #loaded > 0 then
      publish(loaded[1].name)
      busy = false
      return
    end
    query("tags", function(available)
      table.sort(available, function(a, b) return (a.modified_at or "") > (b.modified_at or "") end)
      publish(available[1] and available[1].name)
      busy = false
    end)
  end)
end

function M.current_model()
  M.setup()
  if vim.uv.now() - last_refresh > 5000 or not model then M.refresh() end
  if not model and not warned then
    warned = true
    vim.notify("Ollama model detection pending or unavailable; retry once Ollama is running with a model installed", vim.log.levels.WARN)
  end
  return M.cached_model()
end

function M.setup()
  if M.timer then return end
  M.refresh()
  -- Poll only while local AI is visible or ghost text is active in Insert mode.
  local function active()
    if vim.fn.mode():match("^[iR]") and vim.b.minuet_virtual_text_auto_trigger then return true end
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "codecompanion" then
        local companion = package.loaded["codecompanion"]
        local chat = companion and companion.buf_get_chat(buf)
        if chat and chat.adapter and chat.adapter.name == "ollama" then return true end
      end
    end
    return false
  end
  M.timer = vim.uv.new_timer()
  M.timer:start(5000, 5000, vim.schedule_wrap(function()
    if active() then M.refresh() end
  end))
  vim.api.nvim_create_autocmd({ "InsertEnter", "FocusGained", "BufEnter" }, {
    callback = function()
      if active() and vim.uv.now() - last_refresh > 5000 then M.refresh() end
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    once = true,
    callback = function()
      M.timer:stop()
      M.timer:close()
    end,
  })
end

return M
