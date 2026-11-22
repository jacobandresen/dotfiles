return {
  {
    "folke/snacks.nvim",
    init = function() require("util.pi_issues_ui").setup() end,
    keys = {
      { "<leader>aq", function() require("util.pi_issues").quit() end, desc = "Stop Pi Agents and Quit" },
      {
        "<leader>ai",
        function() require("util.pi_issues_ui").tasks() end,
        desc = "Choose Local Tasks for Pi",
      },
      {
        "<leader>an",
        function() require("util.pi_issues_ui").new_task() end,
        desc = "Write a New Local Task",
      },
      {
        "<leader>aa",
        function() require("util.pi_issues_ui").switch() end,
        desc = "Switch Task (running first)",
      },
      {
        "<leader>ag",
        function() require("util.pi_issues_ui").start_current() end,
        desc = "Start / Focus This Task's Pi",
      },
      {
        "<leader>aw",
        function() require("util.pi_issues_ui").dashboard() end,
        desc = "Pi Task Workspaces",
      },
      {
        "<leader>av",
        function() require("util.pi_issue_edit").open() end,
        desc = "View / Edit Active Task",
      },
      {
        "<leader>ae",
        function() require("util.pi_issue_edit").edit() end,
        desc = "Edit Active Task with Pi",
      },
      {
        "<leader>ap",
        function() require("util.agents").toggle(true) end,
        desc = "Pi Agent",
      },
      {
        "<F6>",
        function()
          vim.cmd.stopinsert()
          require("util.agents").toggle()
        end,
        mode = { "n", "t" },
        desc = "Hide / Show Pi Agent",
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
        desc = "Review Task with Pi Subagent",
      },
    },
  },
}
