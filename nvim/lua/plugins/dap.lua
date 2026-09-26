-- Adapters/configurations for C, C++ and Rust (codelldb) and JS/TS
-- (js-debug) live here; C# is handled by nvim-dap-cs below.
local mason = vim.fn.stdpath("data") .. "/mason"

local function lldb_launch(name, dir)
  return {
    name = name,
    type = "codelldb",
    request = "launch",
    program = function()
      return vim.fn.input("Executable: ", vim.fn.getcwd() .. dir, "file")
    end,
    cwd = "${workspaceFolder}",
    stopOnEntry = false,
  }
end

local lldb_attach = {
  name = "Attach to process",
  type = "codelldb",
  request = "attach",
  pid = function() return require("dap.utils").pick_process() end,
  cwd = "${workspaceFolder}",
}

return {
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      { "rcarriga/nvim-dap-ui", dependencies = { "nvim-neotest/nvim-nio" } },
    },
    -- fkeys: also bind the F13-F60 names some terminals send (turbo/init.lua)
    keys = require("turbo").fkey_specs({
      -- Turbo Pascal 7.0 layout (Run and Debug menus, lua/turbo/menus.lua),
      -- plus Delphi's Shift+F8 for step out, which TP lacked
      { "<C-F9>", function() require("dap").continue() end,              desc = "Run" },
      { "<F8>",   function() require("dap").step_over() end,             desc = "Step Over" },
      { "<F7>",   function() require("dap").step_into() end,             desc = "Trace Into" },
      { "<S-F8>", function() require("dap").step_out() end,              desc = "Step Out" },
      { "<F4>",   function() require("dap").run_to_cursor() end,         desc = "Go to Cursor" },
      { "<C-F2>", function() require("dap").terminate() end,             desc = "Program Reset" },
      { "<C-F8>", function() require("dap").toggle_breakpoint() end,     desc = "Toggle Breakpoint" },
      { "<C-F3>", function() require("dapui").float_element("stacks", { enter = true }) end, desc = "Call Stack" },
      { "<C-F4>", function() require("dapui").eval(nil, { enter = true }) end, desc = "Evaluate/Modify", mode = { "n", "v" } },
      { "<C-F7>", function() require("dapui").elements.watches.add(vim.fn.expand("<cword>")) end, desc = "Add Watch" },
      { "<M-F5>", function() require("dapui").toggle() end,              desc = "User Screen" },

      -- Breakpoints
      { "<leader>db",  function() require("dap").toggle_breakpoint() end, desc = "Toggle Breakpoint" },
      { "<leader>dB",  function() require("dap").set_breakpoint(vim.fn.input("Condition: ")) end, desc = "Conditional Breakpoint" },
      { "<leader>dl",  function() require("dap").set_breakpoint(nil, nil, vim.fn.input("Log: ")) end, desc = "Logpoint" },
      { "<leader>dC",  function() require("dap").clear_breakpoints() end, desc = "Clear Breakpoints" },

      -- Session / UI
      { "<leader>dr",  function() require("dap").restart() end,          desc = "Restart" },
      { "<leader>du",  function() require("dapui").toggle() end,         desc = "Toggle UI" },
      { "<leader>de",  function() require("dapui").eval() end,           desc = "Eval", mode = { "n", "v" } },
      { "<leader>dR",  function() require("dap").repl.open() end,        desc = "REPL" },
    }),
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
      -- TP marks breakpoint lines red and the execution point with a cyan bar
      vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DiagnosticError", linehl = "DapBreakpointLine" })
      vim.fn.sign_define("DapBreakpointCondition", { text = "◆", texthl = "DiagnosticError", linehl = "DapBreakpointLine" })
      vim.fn.sign_define("DapLogPoint", { text = "◉", texthl = "DiagnosticInfo" })
      vim.fn.sign_define("DapStopped", { text = "▶", texthl = "DiagnosticHint", linehl = "DapStoppedLine" })

      dap.listeners.after.event_initialized["dapui_config"] = function() dapui.open() end
      dap.listeners.before.event_terminated["dapui_config"] = function() dapui.close() end
      dap.listeners.before.event_exited["dapui_config"] = function() dapui.close() end

      dap.adapters.codelldb = {
        type = "server",
        port = "${port}",
        executable = { command = mason .. "/bin/codelldb", args = { "--port", "${port}" } },
      }
      dap.configurations.c = { lldb_launch("Launch", "/"), lldb_attach }
      dap.configurations.cpp = dap.configurations.c
      dap.configurations.rust = {
        lldb_launch("Launch binary", "/target/debug/"),
        lldb_launch("Launch binary (release)", "/target/release/"),
        lldb_attach,
      }

      -- js-debug's DAP server, as installed by Mason
      for _, adapter in ipairs({ "pwa-node", "pwa-chrome" }) do
        dap.adapters[adapter] = {
          type = "server",
          host = "localhost",
          port = "${port}",
          executable = {
            command = "node",
            args = { mason .. "/packages/js-debug-adapter/js-debug/src/dapDebugServer.js", "${port}" },
          },
        }
      end
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
          processId = function() return require("dap.utils").pick_process() end,
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
          path = mason .. "/bin/netcoredbg",
        },
      })
    end,
  },
}
