-- Jupyter notebooks in Neovim.
--
--   molten-nvim   — run code interactively against a Jupyter kernel, inline output
--   jupytext.nvim — open/save .ipynb files as plain (py:percent) text
--   image.nvim    — render plots/images inline (WezTerm's kitty graphics protocol)
--
-- The Python host + a "neovim" kernel are provisioned by `make setup-jupyter`
-- (a venv at ~/.virtualenvs/neovim with pynvim + jupyter). options.lua points
-- vim.g.python3_host_prog at it. Run that target BEFORE first launching nvim so
-- molten's `:UpdateRemotePlugins` build step can find pynvim.

return {
  {
    "benlubas/molten-nvim",
    version = "^1.0.0", -- pin to a tag; molten ships breaking changes on main
    dependencies = { "3rd/image.nvim" },
    build = ":UpdateRemotePlugins",
    init = function()
      -- render images through image.nvim (kitty protocol via WezTerm)
      vim.g.molten_image_provider = "image.nvim"
      -- show output as virtual text below the cell instead of a floating window;
      -- pop the float open only when you ask for it
      vim.g.molten_virt_text_output = true
      vim.g.molten_virt_lines_off_by_1 = true -- play nice with jupytext cell markers
      vim.g.molten_auto_open_output = false
      vim.g.molten_wrap_output = true
      vim.g.molten_output_win_max_height = 20
    end,
    keys = {
      { "<leader>ji", "<cmd>MoltenInit<cr>",                    desc = "Jupyter: init kernel" },
      { "<leader>jp", "<cmd>MoltenInit python3<cr>",            desc = "Jupyter: init python3 kernel" },
      { "<leader>jr", "<cmd>MoltenEvaluateOperator<cr>",        desc = "Jupyter: run operator",       mode = "n" },
      { "<leader>jl", "<cmd>MoltenEvaluateLine<cr>",            desc = "Jupyter: run line" },
      { "<leader>jv", ":<C-u>MoltenEvaluateVisual<cr>gv",       desc = "Jupyter: run selection",      mode = "v" },
      { "<leader>jc", "<cmd>MoltenReevaluateCell<cr>",          desc = "Jupyter: re-run cell" },
      { "<leader>jo", "<cmd>MoltenShowOutput<cr>",              desc = "Jupyter: show output" },
      { "<leader>jh", "<cmd>MoltenHideOutput<cr>",              desc = "Jupyter: hide output" },
      { "<leader>je", "<cmd>noautocmd MoltenEnterOutput<cr>",   desc = "Jupyter: enter output window" },
      { "<leader>jd", "<cmd>MoltenDelete<cr>",                  desc = "Jupyter: delete cell" },
      { "<leader>jx", "<cmd>MoltenInterrupt<cr>",               desc = "Jupyter: interrupt kernel" },
      { "<leader>jR", "<cmd>MoltenRestart!<cr>",                desc = "Jupyter: restart kernel" },
      { "<leader>jI", "<cmd>MoltenImportOutput<cr>",            desc = "Jupyter: import .ipynb output" },
      { "<leader>jE", "<cmd>MoltenExportOutput!<cr>",           desc = "Jupyter: export output to .ipynb" },
    },
  },

  -- Edit .ipynb files as plain text (py:percent cells). jupytext converts on
  -- read/write transparently; molten runs the `# %%` cells.
  {
    "GCBallesteros/jupytext.nvim",
    lazy = false, -- must register its BufReadCmd before any .ipynb is opened
    opts = {
      style = "percent",
      output_extension = "auto",
      force_ve = "",
    },
  },

  -- Inline image rendering. magick_cli processor uses the ImageMagick CLI so we
  -- don't need the `magick` luarock. WezTerm speaks the kitty graphics protocol.
  {
    "3rd/image.nvim",
    opts = {
      backend = "kitty",
      processor = "magick_cli",
      integrations = {}, -- only used by molten here, not markdown/etc.
      max_width = 100,
      max_height = 12,
      max_height_window_percentage = math.huge,
      max_width_window_percentage = math.huge,
      window_overlap_clear_enabled = true,
      window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "" },
    },
  },
}
