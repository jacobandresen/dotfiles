-- treat .jsonl as json
vim.filetype.add({ extension = { jsonl = "json" } })

-- silently update plugins on startup (no notification, no UI window)
vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  callback = function()
    require("lazy").update({ show = false, wait = false })
  end,
})

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
  callback = function(args)
    vim.opt_local.autoread = true
    local buf = args.buf
    local timer = vim.uv.new_timer()
    timer:start(2000, 2000, vim.schedule_wrap(function()
      if not vim.api.nvim_buf_is_valid(buf) then
        timer:stop()
        timer:close()
        return
      end
      vim.api.nvim_buf_call(buf, function()
        vim.cmd("checktime")
      end)
    end))
    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
      buffer = buf,
      once = true,
      callback = function()
        timer:stop()
        timer:close()
      end,
    })
  end,
})

-- LSP keymaps (supplement LazyVim defaults)
-- Type def, references, implementations, code action, and rename use LazyVim's
-- defaults: gy, gr, gI, <leader>ca, <leader>cr. Only the extras live here.
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local buf = args.buf
    local ok, telescope = pcall(require, "telescope.builtin")
    if not ok then return end
    local map = function(lhs, rhs, desc)
      vim.keymap.set("n", lhs, rhs, { buffer = buf, desc = desc })
    end
    map("ge", function() telescope.diagnostics() end, "LSP diagnostics")
  end,
})
