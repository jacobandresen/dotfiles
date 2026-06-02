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
      -- Extract the first complete JSON object from a string, ignoring any
      -- trailing text the model appends after the closing brace.
      local function extract_json(str)
        local start = str:find("{")
        if not start then return nil end
        local depth, in_str, escape = 0, false, false
        for i = start, #str do
          local c = str:sub(i, i)
          if escape then
            escape = false
          elseif c == "\\" and in_str then
            escape = true
          elseif c == '"' then
            in_str = not in_str
          elseif not in_str then
            if c == "{" then depth = depth + 1
            elseif c == "}" then
              depth = depth - 1
              if depth == 0 then return str:sub(start, i) end
            end
          end
        end
      end

      require("codecompanion").setup({
        adapters = {
          http = {
            lmstudio = function()
              return require("codecompanion.adapters").extend("openai_compatible", {
                name = "lmstudio",
                formatted_name = "LM Studio",
                env = {
                  -- LM Studio's local server (Developer tab → Start Server).
                  -- Default port is 1234; the loaded model is auto-detected
                  -- via /v1/models, so no model ID needs to be hardcoded.
                  url = "http://localhost:1234",
                  api_key = "lm-studio",
                },
                handlers = {
                  -- Strip any trailing prose the model appends after the JSON object
                  -- so that the inline strategy's JSON parser doesn't fail.
                  parse_inline = function(self, data, _)
                    if not data or data.status ~= "success" then return data end
                    local clean = extract_json(data.output or "")
                    if clean then
                      return { status = "success", output = clean }
                    end
                    return data
                  end,
                },
              })
            end,
          },
        },
        strategies = {
          chat = { adapter = "lmstudio" },
          inline = { adapter = "lmstudio" },
        },
      })
    end,
  },
}
