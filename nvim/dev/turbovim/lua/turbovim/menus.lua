local M = {}

function M.get()
  return {
    {
      label = "File", key = "f",
      items = {
        { label = "Open File",    key = "o", hint = "find_files",  action = function() require("telescope.builtin").find_files() end },
        { label = "Recent Files", key = "r", hint = "oldfiles",    action = function() require("telescope.builtin").oldfiles() end },
        { label = "New Buffer",   key = "n", hint = ":enew",       action = function() vim.cmd("enew") end },
        { sep = true },
        { label = "Save",         key = "s", hint = ":w",          action = function() vim.cmd("w") end },
        { label = "Save All",     key = "a", hint = ":wa",         action = function() vim.cmd("wa") end },
        { sep = true },
        { label = "Close Buffer", key = "c", hint = ":bd",         action = function() vim.cmd("bd") end },
        { label = "Quit",         key = "q", hint = ":qa",         action = function() vim.cmd("qa") end },
      },
    },
    {
      label = "Edit", key = "e",
      items = {
        { label = "Undo",           key = "u", hint = "u",     action = function() vim.cmd("undo") end },
        { label = "Redo",           key = "r", hint = "C-r",   action = function() vim.cmd("redo") end },
        { sep = true },
        { label = "Find",           key = "f", hint = "/",     action = function() vim.api.nvim_feedkeys("/", "n", false) end },
        { label = "Find & Replace", key = "s", hint = ":%s/",  action = function() vim.api.nvim_feedkeys(":%s/", "n", false) end },
      },
    },
    {
      label = "Search", key = "s",
      items = {
        { label = "Live Grep",          key = "g", hint = "", action = function() require("telescope.builtin").live_grep() end },
        { label = "In Buffer",          key = "b", hint = "", action = function() require("telescope.builtin").current_buffer_fuzzy_find() end },
        { label = "Document Symbols",   key = "d", hint = "", action = function() require("telescope.builtin").lsp_document_symbols() end },
        { label = "Workspace Symbols",  key = "w", hint = "", action = function() require("telescope.builtin").lsp_workspace_symbols() end },
      },
    },
    {
      label = "Code", key = "c",
      items = {
        { label = "Code Action", key = "a", hint = "",  action = function() vim.lsp.buf.code_action() end },
        { label = "Rename",      key = "r", hint = "",  action = function() vim.lsp.buf.rename() end },
        { label = "Format",      key = "f", hint = "",  action = function() vim.lsp.buf.format({ async = true }) end },
        { label = "Hover Docs",  key = "h", hint = "K", action = function() vim.lsp.buf.hover() end },
        { sep = true },
        { label = "Diagnostics", key = "d", hint = "",  action = function() require("telescope.builtin").diagnostics() end },
        { label = "References",  key = "x", hint = "",  action = function() require("telescope.builtin").lsp_references() end },
        { label = "Go to Def",   key = "g", hint = "gd", action = function() vim.lsp.buf.definition() end },
      },
    },
    {
      label = "Database", key = "d",
      items = {
        { label = "Toggle UI",       key = "d", hint = "DBUIToggle",        action = function() vim.cmd("DBUIToggle") end },
        { label = "Add Connection",  key = "a", hint = "DBUIAddConnection", action = function() vim.cmd("DBUIAddConnection") end },
        { label = "Find Buffer",     key = "f", hint = "DBUIFindBuffer",    action = function() vim.cmd("DBUIFindBuffer") end },
        { label = "Rename Buffer",   key = "r", hint = "DBUIRenameBuffer",  action = function() vim.cmd("DBUIRenameBuffer") end },
        { sep = true },
        { label = "Execute Query",   key = "e", hint = "<leader>S",        action = function() vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<leader>S", true, true, true), "n", false) end },
        { label = "Last Query Info", key = "i", hint = "DBUILastQueryInfo", action = function() vim.cmd("DBUILastQueryInfo") end },
      },
    },
    {
      label = "Debug", key = "b",
      items = {
        { label = "Continue",         key = "c", hint = "F5",        action = function() require("dap").continue() end },
        { label = "Stop",             key = "s", hint = "F4",        action = function() require("dap").terminate() end },
        { label = "Restart",          key = "R", hint = "F9",        action = function() require("dap").restart() end },
        { sep = true },
        { label = "Step Over",        key = "o", hint = "F10",       action = function() require("dap").step_over() end },
        { label = "Step Into",        key = "i", hint = "F11",       action = function() require("dap").step_into() end },
        { label = "Step Out",         key = "u", hint = "F12",       action = function() require("dap").step_out() end },
        { sep = true },
        { label = "Breakpoint",       key = "b", hint = "<leader>db", action = function() require("dap").toggle_breakpoint() end },
        { label = "Cond. Breakpoint", key = "B", hint = "<leader>dB", action = function() require("dap").set_breakpoint(vim.fn.input("Condition: ")) end },
        { label = "Clear Breakpoints",key = "x", hint = "<leader>dC", action = function() require("dap").clear_breakpoints() end },
        { sep = true },
        { label = "Toggle UI",        key = "U", hint = "<leader>du", action = function() require("dapui").toggle() end },
        { label = "Eval",             key = "e", hint = "<leader>de", action = function() require("dapui").eval() end },
        { label = "REPL",             key = "r", hint = "<leader>dr", action = function() require("dap").repl.open() end },
      },
    },
    {
      label = "Run", key = "r",
      items = {
        { label = "Make", key = "m", hint = ":make", action = function() vim.cmd("make") end },
      },
    },
    {
      label = "AI", key = "a",
      items = {
        { label = "Chat",    key = "c", hint = "<leader>cc", action = function() vim.cmd("CodeCompanionChat Toggle") end },
        { label = "Actions", key = "a", hint = "<leader>ca", action = function() vim.cmd("CodeCompanionActions") end },
        { label = "Inline",  key = "i", hint = "<leader>ci", action = function() vim.cmd("CodeCompanion") end },
      },
    },
    {
      label = "Window", key = "w",
      items = {
        { label = "Split Horiz",  key = "h", hint = ":sp",    action = function() vim.cmd("split") end },
        { label = "Split Vert",   key = "v", hint = ":vsp",   action = function() vim.cmd("vsplit") end },
        { sep = true },
        { label = "Close",        key = "c", hint = ":q",     action = function() vim.cmd("q") end },
        { label = "Close Others", key = "o", hint = ":only",  action = function() vim.cmd("only") end },
        { sep = true },
        { label = "Move Left",    key = "l", hint = "C-w h",  action = function() vim.cmd("wincmd h") end },
        { label = "Move Right",   key = "r", hint = "C-w l",  action = function() vim.cmd("wincmd l") end },
        { label = "Move Up",      key = "u", hint = "C-w k",  action = function() vim.cmd("wincmd k") end },
        { label = "Move Down",    key = "d", hint = "C-w j",  action = function() vim.cmd("wincmd j") end },
      },
    },
    {
      label = "Help", key = "h",
      items = {
        { label = "Keymaps",       key = "k", hint = "", action = function() require("telescope.builtin").keymaps() end },
        { label = "Commands",      key = "c", hint = "", action = function() require("telescope.builtin").commands() end },
        { label = "Check Health",  key = "h", hint = "", action = function() vim.cmd("checkhealth") end },
        { label = "Mason",         key = "m", hint = "", action = function() vim.cmd("Mason") end },
        { sep = true },
        { label = "About TurboVim",key = "a", hint = "", action = function() require("turbovim.splash").show() end },
      },
    },
  }
end

return M
