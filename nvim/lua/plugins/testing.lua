return {
  {
    "nvim-neotest/neotest",
    lazy = true,
    dependencies = {
      "nvim-neotest/nvim-nio",
      "nvim-treesitter/nvim-treesitter",
      "nvim-neotest/neotest-python",
      "marilari88/neotest-vitest",
      "nvim-neotest/neotest-jest",
      "Issafalcon/neotest-dotnet",
      "mrcjkb/rustaceanvim",
      "nvim-lua/plenary.nvim",
    },
    cmd = "TestView",
    keys = {
      { "<leader>ts", function() require("util.testing").toggle_view() end, desc = "Test Explorer and Output" },
      { "<leader>tt", function() require("util.testing").run_file() end, desc = "Run Test File" },
      { "<leader>tr", function() require("util.testing").run_nearest() end, desc = "Run Nearest Test" },
      { "<leader>tT", function() require("util.testing").run_directory() end, desc = "Run Tests in This Directory" },
      { "<leader>tl", function() require("neotest").run.run_last() end, desc = "Rerun Last Test" },
      { "<leader>tS", function() require("neotest").run.stop() end, desc = "Stop Test Run" },
      { "<leader>ta", function() require("neotest").run.attach() end, desc = "Attach to Running Test" },
      {
        "<leader>to",
        function() require("neotest").output.open({ enter = true, auto_close = false }) end,
        desc = "Test Output",
      },
      { "<leader>tO", function() require("neotest").output_panel.toggle() end, desc = "Toggle Test Output Panel" },
      {
        "<leader>tw",
        function() require("neotest").watch.toggle(vim.api.nvim_buf_get_name(0)) end,
        desc = "Watch Test File",
      },
    },
    opts = function()
      local testing = require("util.testing")
      local python = require("neotest-python")({
        args = function(runner) return runner == "pytest" and { "-vv", "-s" } or {} end,
      })
      python.name = "Python"
      return {
        consumers = {
          test_output = require("util.test_output"),
          test_workspace = require("util.test_workspace"),
        },
        default_strategy = require("util.test_output").strategy,
        adapters = {
          testing.dotnet_adapter(),
          python,
          testing.node_adapter("vitest"),
          testing.node_adapter("jest"),
          testing.rust_adapter(),
        },
        discovery = { concurrent = 2, filter_dir = testing.filter_dir },
        summary = {
          animated = false,
          count = true,
          open = testing.open_summary,
          mappings = {
            run = { "r", "<leader>tr" },
            stop = { "u", "<leader>tS" },
            attach = { "a", "<leader>ta" },
            output = { "o", "<leader>to" },
          },
        },
        output_panel = { enabled = false },
        floating = { border = "rounded", max_width = 0.85, max_height = 0.75 },
        status = { signs = true, virtual_text = false },
        output = { open_on_run = false },
        quickfix = { open = false },
      }
    end,
    config = function(_, opts)
      local neotest = require("neotest")
      require("util.testing").configure_summary()
      neotest.setup(opts)
      local run = neotest.run.run
      local run_last, stop = neotest.run.run_last, neotest.run.stop
      local last_directory
      neotest.run.run = function(args)
        local selection = type(args) == "string" and { args } or args or {}
        local path = selection[1]
        local stat = path and vim.uv.fs_stat(path)
        if stat and stat.type == "directory" then
          last_directory = vim.deepcopy(selection)
          return neotest.test_workspace.run_directory(path, selection, run)
        end
        last_directory = nil
        return run(args)
      end
      neotest.run.run_last = function(args)
        if last_directory then return neotest.run.run(vim.tbl_extend("force", last_directory, args or {})) end
        return run_last(args)
      end
      neotest.run.stop = function(args)
        local selection = type(args) == "string" and { args } or args or {}
        local path = selection[1]
        local stat = path and vim.uv.fs_stat(path)
        if stat and stat.type == "directory" then return neotest.test_workspace.stop_directory(path) end
        return stop(args)
      end
      neotest.output_panel = neotest.test_output
      neotest.output.open = neotest.test_output.show
      neotest.run.attach = neotest.test_output.attach
      vim.api.nvim_create_user_command("TestView", function(args)
        if args.args ~= "" or args.bang then
          require("util.testing").open_view(args.args ~= "" and vim.fn.expand(args.args) or nil, args.bang)
        else
          require("util.testing").toggle_view()
        end
      end, { nargs = "?", complete = "dir", bang = true })
    end,
  },
}
