-- AI assistant via CodeCompanion.nvim, switchable between Ollama (whichever
-- model is currently loaded) and GitHub Copilot with `ga` inside the chat buffer.
local function ollama_model()
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

  -- prefer whatever Ollama currently has resident in memory
  local loaded = models_from("http://localhost:11434/api/ps")
  if loaded then
    return loaded[1].name
  end

  -- nothing loaded right now (idle unload, fresh server, ...) - fall back to
  -- the most recently pulled model rather than guessing a hardcoded name
  local available = models_from("http://localhost:11434/api/tags")
  if available then
    table.sort(available, function(a, b)
      return a.modified_at > b.modified_at
    end)
    vim.notify("Ollama: no model currently loaded, defaulting to " .. available[1].name, vim.log.levels.WARN)
    return available[1].name
  end

  vim.notify("Ollama unreachable at localhost:11434 - AI commands will fail until it's running", vim.log.levels.WARN)
  return "unknown"
end

return {
  {
    -- Not used for inline ghost-text (disabled below) - installed purely so
    -- `:Copilot auth` can produce the OAuth token CodeCompanion's copilot
    -- adapter reads. Run `:Copilot auth` once after install.
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    opts = {
      suggestion = { enabled = false },
      panel = { enabled = false },
    },
  },
  {
    "olimorris/codecompanion.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>ac", "<cmd>CodeCompanionChat Toggle<cr>", desc = "Toggle AI chat", mode = { "n", "v" } },
      { "<leader>an", "<cmd>CodeCompanionChat<cr>", desc = "New AI chat" },
      { "<leader>ap", "<cmd>CodeCompanionChat Add<cr>", desc = "Add selection to AI chat", mode = "v" },
      { "<leader>ai", "<cmd>CodeCompanion<cr>", desc = "Inline AI edit", mode = { "n", "v" } },
      -- Explain/fix/tests/etc. live in the action palette (ships built in,
      -- no custom hooks needed the way gp.nvim required for GpExplain).
      { "<leader>aa", "<cmd>CodeCompanionActions<cr>", desc = "AI actions", mode = { "n", "v" } },
    },
    config = function()
      require("codecompanion").setup({
        adapters = {
          http = {
            ollama = function()
              return require("codecompanion.adapters").extend("ollama", {
                schema = {
                  model = { default = ollama_model() },
                },
              })
            end,
          },
        },
        interactions = {
          chat = { adapter = "ollama" },
          inline = { adapter = "ollama" },
        },
      })
    end,
  },
}
