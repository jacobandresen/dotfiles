return {
  { "mfussenegger/nvim-dap", lazy = true },
  { "nvim-neotest/nvim-nio", lazy = true },

  {
    "rcarriga/nvim-dap-ui",
    dependencies = { "mfussenegger/nvim-dap", "nvim-neotest/nvim-nio" },
    keys = {
      { "<F5>",       function() require("dap").continue() end,             desc = "Debug: Continue" },
      { "<F4>",       function() require("dap").terminate() end,            desc = "Debug: Stop" },
      { "<F9>",       function() require("dap").restart() end,              desc = "Debug: Restart" },
      { "<F10>",      function() require("dap").step_over() end,            desc = "Debug: Step Over" },
      { "<F11>",      function() require("dap").step_into() end,            desc = "Debug: Step Into" },
      { "<F12>",      function() require("dap").step_out() end,             desc = "Debug: Step Out" },
      { "<leader>db", function() require("dap").toggle_breakpoint() end,    desc = "Debug: Toggle Breakpoint" },
      { "<leader>dB", function() require("dap").set_breakpoint(vim.fn.input("Condition: ")) end, desc = "Debug: Conditional Breakpoint" },
      { "<leader>dl", function() require("dap").set_breakpoint(nil, nil, vim.fn.input("Log: ")) end, desc = "Debug: Logpoint" },
      { "<leader>dC", function() require("dap").clear_breakpoints() end,    desc = "Debug: Clear Breakpoints" },
      { "<leader>du", function() require("dapui").toggle() end,             desc = "Debug: Toggle UI" },
      { "<leader>de", function() require("dapui").eval() end,               desc = "Debug: Eval",               mode = { "n", "v" } },
      { "<leader>dr", function() require("dap").repl.open() end,            desc = "Debug: REPL" },
    },
    config = function()
      local dap, dapui = require("dap"), require("dapui")
      dapui.setup({
        icons = { expanded = "▾", collapsed = "▸", current_frame = "▸" },
        mappings = {
          expand = { "<CR>", "<2-LeftMouse>" },
          open = "o",
          remove = "d",
          edit = "e",
          repl = "r",
          toggle = "t",
        },
        layouts = {
          {
            elements = {
              { id = "scopes",      size = 0.35 },
              { id = "breakpoints", size = 0.20 },
              { id = "stacks",      size = 0.25 },
              { id = "watches",     size = 0.20 },
            },
            size = 45,
            position = "left",
          },
          {
            elements = {
              { id = "repl",    size = 0.5 },
              { id = "console", size = 0.5 },
            },
            size = 12,
            position = "bottom",
          },
        },
        floating = {
          max_height = 0.9,
          max_width = 0.9,
          border = "rounded",
          mappings = { close = { "q", "<Esc>" } },
        },
      })
      dap.listeners.after.event_initialized["dapui_config"] = function() dapui.open() end
      dap.listeners.before.event_terminated["dapui_config"] = function() dapui.close() end
      dap.listeners.before.event_exited["dapui_config"] = function() dapui.close() end
    end,
  },

  {
    "mfussenegger/nvim-dap",
    ft = { "c", "cpp" },
    config = function()
      local dap = require("dap")
      local codelldb = vim.fn.stdpath("data") .. "/mason/bin/codelldb"

      dap.adapters.codelldb = {
        type = "server",
        port = "${port}",
        executable = { command = codelldb, args = { "--port", "${port}" } },
      }

      dap.configurations.c = {
        {
          name = "Launch",
          type = "codelldb",
          request = "launch",
          program = function()
            return vim.fn.input("Executable: ", vim.fn.getcwd() .. "/", "file")
          end,
          cwd = "${workspaceFolder}",
          stopOnEntry = false,
        },
        {
          name = "Attach to process",
          type = "codelldb",
          request = "attach",
          pid = function() return require("dap.utils").pick_process() end,
          cwd = "${workspaceFolder}",
        },
      }

      dap.configurations.cpp = dap.configurations.c
    end,
  },

  {
    "mfussenegger/nvim-dap",
    ft = { "rust" },
    config = function()
      local dap = require("dap")
      local codelldb = vim.fn.stdpath("data") .. "/mason/bin/codelldb"

      dap.adapters.codelldb = dap.adapters.codelldb or {
        type = "server",
        port = "${port}",
        executable = { command = codelldb, args = { "--port", "${port}" } },
      }

      dap.configurations.rust = {
        {
          name = "Launch binary",
          type = "codelldb",
          request = "launch",
          program = function()
            return vim.fn.input("Executable: ", vim.fn.getcwd() .. "/target/debug/", "file")
          end,
          cwd = "${workspaceFolder}",
          stopOnEntry = false,
        },
        {
          name = "Launch binary (release)",
          type = "codelldb",
          request = "launch",
          program = function()
            return vim.fn.input("Executable: ", vim.fn.getcwd() .. "/target/release/", "file")
          end,
          cwd = "${workspaceFolder}",
          stopOnEntry = false,
        },
        {
          name = "Attach to process",
          type = "codelldb",
          request = "attach",
          pid = function() return require("dap.utils").pick_process() end,
          cwd = "${workspaceFolder}",
        },
      }
    end,
  },

  {
    "mxsdev/nvim-dap-vscode-js",
    dependencies = { "mfussenegger/nvim-dap" },
    ft = { "javascript", "typescript", "javascriptreact", "typescriptreact" },
    config = function()
      require("dap-vscode-js").setup({
        debugger_path = vim.fn.stdpath("data") .. "/mason/packages/js-debug-adapter",
        adapters = { "pwa-node", "pwa-chrome" },
      })

      local dap = require("dap")
      local js_config = {
        {
          name = "Launch file",
          type = "pwa-node",
          request = "launch",
          program = "${file}",
          cwd = "${workspaceFolder}",
          sourceMaps = true,
          resolveSourceMapLocations = { "${workspaceFolder}/**", "!**/node_modules/**" },
        },
        {
          name = "Attach",
          type = "pwa-node",
          request = "attach",
          processId = require("dap.utils").pick_process,
          cwd = "${workspaceFolder}",
          sourceMaps = true,
        },
        {
          name = "Launch Chrome",
          type = "pwa-chrome",
          request = "launch",
          url = function()
            return vim.fn.input("URL: ", "http://localhost:3000")
          end,
          webRoot = "${workspaceFolder}",
          sourceMaps = true,
        },
      }

      for _, lang in ipairs({ "javascript", "typescript", "javascriptreact", "typescriptreact" }) do
        dap.configurations[lang] = js_config
      end
    end,
  },

  {
    "NicholasMata/nvim-dap-cs",
    dependencies = { "mfussenegger/nvim-dap" },
    ft = { "cs" },
    config = function()
      require("dap-cs").setup({
        dap_configurations = {
          {
            type = "coreclr",
            name = "Launch",
            request = "launch",
            program = function()
              return vim.fn.input("Path to dll: ", vim.fn.getcwd() .. "/bin/Debug/", "file")
            end,
            cwd = "${workspaceFolder}",
            stopAtEntry = false,
          },
          {
            type = "coreclr",
            name = "Attach to process",
            request = "attach",
          },
        },
        netcoredbg = {
          path = vim.fn.stdpath("data") .. "/mason/bin/netcoredbg",
        },
      })
    end,
  },
}
