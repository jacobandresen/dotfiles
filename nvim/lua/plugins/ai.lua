return {
  {
    "folke/snacks.nvim",
    init = function() require("util.pi_issues_ui").setup() end,
    keys = {
      { "<leader>aq", function() require("util.pi_issues").quit() end, desc = "Stop Pi Agents and Quit" },
      {
        "<leader>ai",
        function() require("util.pi_issues_ui").issues() end,
        desc = "Choose Issues for Pi",
      },
      {
        "<leader>aw",
        function() require("util.pi_issues_ui").dashboard() end,
        desc = "Pi Issue Workspaces",
      },
      {
        "<leader>ap",
        function() require("util.agents").toggle() end,
        desc = "Pi Agent",
      },
      {
        "<leader>as",
        function() require("util.agents").send(false) end,
        desc = "Send File to Pi",
      },
      {
        "<leader>as",
        function() require("util.agents").send(true) end,
        mode = "x",
        desc = "Send Selection to Pi",
      },
      {
        "<leader>ar",
        function() require("util.agents").review() end,
        desc = "Review Issue with Pi Subagent",
      },
    },
  },
}
