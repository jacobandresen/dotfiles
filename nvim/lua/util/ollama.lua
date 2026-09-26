-- Shared helper: auto-detect whichever model Ollama currently has loaded.
-- Used by both the CodeCompanion chat adapter (ai.lua) and Minuet's inline
-- suggestions (ai.lua) so switching models via `make use-model` in the repo
-- root doesn't require editing either plugin config.
local M = {}

local function models_from(url)
  local out = vim.fn.system({ "curl", "-s", "--max-time", "2", url })
  if vim.v.shell_error ~= 0 or out == "" then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, out)
  if not ok or not decoded.models or #decoded.models == 0 then
    return nil
  end
  return decoded.models
end

function M.current_model()
  -- prefer whatever Ollama currently has resident in memory
  local loaded = models_from("http://localhost:11434/api/ps")
  if loaded then
    return loaded[1].name
  end

  -- nothing loaded right now (Ollama unloads idle models, so this is the
  -- normal state) - use the most recently pulled model; Ollama loads it on
  -- the first request
  local available = models_from("http://localhost:11434/api/tags")
  if available then
    table.sort(available, function(a, b)
      return a.modified_at > b.modified_at
    end)
    return available[1].name
  end

  vim.notify("Ollama unreachable at localhost:11434 - AI commands will fail until it's running", vim.log.levels.WARN)
  return "unknown"
end

return M
