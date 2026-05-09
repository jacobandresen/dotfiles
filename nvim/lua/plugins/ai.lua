local function extract_content(content)
  if type(content) == "string" then
    return content
  elseif type(content) == "table" then
    local parts = {}
    for _, part in ipairs(content) do
      if type(part) == "table" and part.text then
        table.insert(parts, part.text)
      elseif type(part) == "string" then
        table.insert(parts, part)
      end
    end
    return table.concat(parts, "\n")
  end
  return ""
end

return {
  {
    "olimorris/codecompanion.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    keys = {
      { "<leader>cc", "<cmd>CodeCompanionChat Toggle<cr>", desc = "Toggle AI chat" },
      { "<leader>ca", "<cmd>CodeCompanionActions<cr>", desc = "AI actions", mode = { "n", "v" } },
      { "<leader>ci", "<cmd>CodeCompanion<cr>", desc = "Inline AI", mode = { "n", "v" } },
    },
    config = function()
      require("codecompanion").setup({
        adapters = {
          pi = function()
            return {
              name = "pi",
              formatted_name = "Pi",
              roles = { llm = "assistant", user = "user" },
              opts = {
                stream = false,
                request = function(client, payload, actions, _)
                  local messages = payload.messages or {}
                  local sys_prompt = nil
                  local conv = {}

                  for _, msg in ipairs(messages) do
                    if msg.role == "system" then
                      sys_prompt = extract_content(msg.content)
                    elseif msg.role == "user" then
                      table.insert(conv, "Human: " .. extract_content(msg.content))
                    else
                      table.insert(conv, "Assistant: " .. extract_content(msg.content))
                    end
                  end

                  local cmd = { "pi", "--print", "--no-session", "--no-builtin-tools" }
                  if sys_prompt and sys_prompt ~= "" then
                    vim.list_extend(cmd, { "--append-system-prompt", sys_prompt })
                  end

                  local chunks = {}
                  local job = vim.system(
                    cmd,
                    {
                      stdin = table.concat(conv, "\n\n"),
                      stdout = function(_, data)
                        if data then table.insert(chunks, data) end
                      end,
                    },
                    function(result)
                      if result.code == 0 then
                        actions.callback(nil, table.concat(chunks))
                      else
                        actions.callback("pi error (exit " .. result.code .. "): " .. (result.stderr or ""), nil)
                      end
                      actions.done()
                    end
                  )

                  return { shutdown = function() job:kill(15) end }
                end,
              },
              features = { text = true, tokens = false },
              url = "",
              headers = {},
              handlers = {
                setup = function(self)
                  self.opts.stream = false
                  return true
                end,
                form_parameters = function() return {} end,
                form_messages = function(_, messages) return { messages = messages } end,
                chat_output = function(_, data)
                  if not data or data == "" then return nil end
                  return {
                    status = "success",
                    output = { role = "assistant", content = data },
                  }
                end,
                inline_output = function(_, data, _) return data end,
                on_exit = function() end,
              },
              schema = {
                model = {
                  order = 1,
                  mapping = "parameters",
                  type = "str",
                  desc = "Pi model (set via --model flag)",
                  default = "default",
                },
              },
            }
          end,
        },
        strategies = {
          chat = { adapter = "pi" },
          inline = { adapter = "pi" },
          agent = { adapter = "pi" },
        },
      })
    end,
  },
}
