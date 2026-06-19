return {
  -- ensure parsers for every language we debug/edit are installed.
  -- LazyVim's defaults cover c/cpp/json/lua/etc.; c_sharp, rust, and java are
  -- only pulled in by their lang extras, so add them explicitly here.
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "c_sharp", "rust", "java", "javascript", "typescript", "tsx",
      })
    end,
  },
}
