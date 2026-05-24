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
      { "<leader>ac", "<cmd>CodeCompanionChat Toggle<cr>", desc = "AI chat (toggle)" },
      { "<leader>aa", "<cmd>CodeCompanionActions<cr>", desc = "AI actions", mode = { "n", "v" } },
      { "<leader>ai", "<cmd>CodeCompanion<cr>", desc = "AI inline", mode = { "n", "v" } },
    },
    config = function()
      require("codecompanion").setup({
        adapters = {
          http = {
            pi = function()
              return {
                name = "pi",
                formatted_name = "Pi",
                roles = { llm = "assistant", user = "user" },
                opts = {
                  stream = true,
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

                    local thinking = client.adapter.schema.thinking
                      and client.adapter.schema.thinking.default
                      or "medium"

                    local cmd = {
                      "pi", "--print", "--no-session",
                      "--tools", "read,bash,edit,write,grep,find,ls",
                      "--thinking", thinking,
                    }
                    if sys_prompt and sys_prompt ~= "" then
                      vim.list_extend(cmd, { "--append-system-prompt", sys_prompt })
                    end

                    local job = vim.system(
                      cmd,
                      {
                        stdin = table.concat(conv, "\n\n"),
                        stdout = vim.schedule_wrap(function(_, data)
                          if data and data ~= "" then
                            actions.callback(nil, data)
                          end
                        end),
                      },
                      vim.schedule_wrap(function(result)
                        if result.code ~= 0 then
                          actions.callback(
                            "pi error (exit " .. result.code .. "): " .. (result.stderr or ""),
                            nil
                          )
                        end
                        actions.done()
                      end)
                    )

                    return { shutdown = function() job:kill(15) end }
                  end,
                },
                features = { text = true, tokens = false },
                url = "",
                headers = {},
                handlers = {
                  setup = function()
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
                  inline_output = function(_, data, _)
                    if not data or data == "" then return nil end
                    return { status = "success", output = data }
                  end,
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
                  thinking = {
                    order = 2,
                    mapping = "parameters",
                    type = "str",
                    desc = "Thinking level: off, minimal, low, medium, high, xhigh",
                    default = "medium",
                  },
                },
              }
            end,
          },
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
