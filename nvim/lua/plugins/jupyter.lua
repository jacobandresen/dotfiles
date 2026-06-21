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
    config = function(_, opts)
      require("jupytext").setup(opts)

      -- Drop a notebook into visual mode for quick cell selection — but only
      -- when a Molten kernel is actually live for that buffer ("jupyter is
      -- responding"). pcall guards MoltenRunningKernels, a remote-plugin fn that
      -- isn't registered until molten loads; it returns [] with no kernel.
      local function enter_visual_if_live(buf)
        if not (vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf):match("%.ipynb$")) then
          return
        end
        local ok, kernels = pcall(vim.fn.MoltenRunningKernels, true)
        if not (ok and type(kernels) == "table" and #kernels > 0) then return end
        vim.schedule(function()
          if vim.api.nvim_get_current_buf() == buf and vim.api.nvim_get_mode().mode == "n" then
            vim.api.nvim_feedkeys("v", "n", false)
          end
        end)
      end

      -- Switching back to a notebook that already has a running kernel. Once per
      -- buffer so it doesn't re-fire on every window switch. jupytext keeps the
      -- .ipynb buffer name, so the pattern matches after the py:percent convert.
      vim.api.nvim_create_autocmd("BufWinEnter", {
        pattern = "*.ipynb",
        desc = "Notebook -> visual mode (if its kernel is live)",
        callback = function(args)
          if vim.b[args.buf].notebook_visual_entered then return end
          vim.b[args.buf].notebook_visual_entered = true
          enter_visual_if_live(args.buf)
        end,
      })

      -- The normal flow: open notebook -> :MoltenInit -> kernel connects. Molten
      -- fires User MoltenKernelReady once it's responding; enter visual mode then.
      vim.api.nvim_create_autocmd("User", {
        pattern = "MoltenKernelReady",
        desc = "Notebook -> visual mode once its kernel responds",
        callback = function()
          enter_visual_if_live(vim.api.nvim_get_current_buf())
        end,
      })
    end,
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
