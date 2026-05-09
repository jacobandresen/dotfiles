-- treat .jsonl as json
vim.filetype.add({ extension = { jsonl = "json" } })

-- use jq as formatprg for json files
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "json" },
  callback = function()
    vim.api.nvim_set_option_value("formatprg", "jq", { scope = "local" })
  end,
})

-- enable inlay hints on LSP attach
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client and client:supports_method("textDocument/inlayHint") then
      vim.lsp.inlay_hint.enable(true, { bufnr = args.buf })
    end
  end,
})

-- auto-refresh log/jsonl files every 2 seconds
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = { "*.log", "*.jsonl" },
  callback = function()
    vim.opt_local.autoread = true
    local timer = vim.uv.new_timer()
    timer:start(2000, 2000, vim.schedule_wrap(function()
      if vim.api.nvim_buf_is_valid(vim.api.nvim_get_current_buf()) then
        vim.cmd("checktime")
      end
    end))
  end,
})

-- LSP keymaps (supplement LazyVim defaults)
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local buf = args.buf
    local ok, telescope = pcall(require, "telescope.builtin")
    if not ok then return end
    local map = function(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, { buffer = buf, desc = desc })
    end
    map("go",          function() telescope.lsp_type_definitions() end,  "LSP type definitions")
    map("gR",          function() telescope.lsp_references() end,        "LSP references")
    map("gi",          function() telescope.lsp_implementations() end,   "LSP implementations")
    map("ge",          function() telescope.diagnostics() end,           "LSP diagnostics")
    map("<leader>vws", function() vim.lsp.buf.workspace_symbol() end,    "Workspace symbol")
    map("<leader>xca", function() vim.lsp.buf.code_action() end,         "Code action")
    map("<leader>xrn", function() vim.lsp.buf.rename() end,              "Rename")
  end,
})
