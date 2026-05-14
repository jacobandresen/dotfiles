return {
  -- ensure rust-analyzer is installed via mason
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "rust-analyzer" })
    end,
  },

  -- rustaceanvim: Rust LSP, inlay hints, macro expansion, codelldb DAP
  {
    "mrcjkb/rustaceanvim",
    version = "^5",
    ft = { "rust" },
    keys = {
      { "<leader>rb", "<cmd>make build<cr>", ft = "rust", desc = "Cargo build" },
    },
    init = function()
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "rust",
        callback = function() vim.bo.makeprg = "cargo" end,
      })
    end,
    config = function()
      vim.g.rustaceanvim = {
        server = {
          default_settings = {
            ["rust-analyzer"] = {
              cargo = {
                allFeatures = true,
                loadOutDirsFromCheck = true,
              },
              checkOnSave = { command = "clippy" },
              procMacro = { enable = true },
              inlayHints = {
                bindingModeHints = { enable = true },
                closureCaptureHints = { enable = true },
                closureReturnTypeHints = { enable = "always" },
                lifetimeElisionHints = { enable = "skip_trivial" },
              },
            },
          },
        },
      }
    end,
  },
}
