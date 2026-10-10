return {
  {
    "folke/snacks.nvim",
    keys = {
      { "<leader>ap", function() require("util.agents").toggle() end, desc = "Pi Agent" },
      { "<leader>as", function() require("util.agents").send(false) end, desc = "Send File to Pi" },
      { "<leader>as", function() require("util.agents").send(true) end, mode = "x", desc = "Send Selection to Pi" },
    },
  },
}
