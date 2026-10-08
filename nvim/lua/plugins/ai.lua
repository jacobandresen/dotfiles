-- AI: coding agents (pi, Claude Code, Codex) run as CLIs in a terminal split
-- (util/agents.lua); Copilot supplies inline ghost text. Run `:Copilot auth`
-- once after install.
return {
  {
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    event = "InsertEnter",
    opts = {
      panel = { enabled = false },
      suggestion = {
        auto_trigger = true,
        keymap = {
          accept = "<A-A>",
          accept_line = "<A-a>",
          next = "<A-]>",
          prev = "<A-[>",
          dismiss = "<A-e>",
        },
      },
      filetypes = { markdown = true, help = false, gitcommit = false, ["."] = false },
    },
  },

  -- the agents live in util/agents.lua; keys are always available
  {
    "folke/snacks.nvim",
    keys = {
      { "<leader>a", "", desc = "+ai", mode = { "n", "x" } },
      { "<leader>ap", function() require("util.agents").toggle("pi") end, desc = "Pi Agent" },
      { "<leader>ac", function() require("util.agents").toggle("claude") end, desc = "Claude Code" },
      { "<leader>ax", function() require("util.agents").toggle("codex") end, desc = "Codex" },
      { "<leader>as", function() require("util.agents").send(false) end, desc = "Send File to Agent" },
      { "<leader>as", function() require("util.agents").send(true) end, mode = "x", desc = "Send Selection to Agent" },
      { "<leader>ag", function() require("util.agents").toggle_ghost() end, desc = "Toggle Copilot Ghost Text" },
    },
  },
}
