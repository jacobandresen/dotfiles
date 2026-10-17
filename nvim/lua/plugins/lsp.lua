local function roslyn_needs_mason()
  local mason_bin = vim.fn.stdpath("data") .. "/mason/bin/roslyn-language-server"
  return vim.fn.executable("roslyn-language-server") ~= 1 and vim.fn.executable(mason_bin) ~= 1
end

return {
  -- mason: non-LSP tools. LSP servers listed under nvim-lspconfig below are
  -- installed automatically by LazyVim.
  {
    "mason-org/mason.nvim",
    opts = {
      ensure_installed = {
        "rust-analyzer", -- started by rustaceanvim, not lspconfig
        "netcoredbg",
        "codelldb",
        "js-debug-adapter",
        "prettier",
        "black",
        "isort",
        "clang-format",
        "goimports",
        "csharpier",
      },
    },
  },

  -- helm syntax
  { "towolf/vim-helm", ft = "helm" },

  {
    "neovim/nvim-lspconfig",
    opts = {
      diagnostics = { virtual_text = false },
      servers = {
        -- These servers expose file-wide fix actions. ESLint and Biome only
        -- start in projects with their respective config files.
        gopls = {},
        eslint = {},
        biome = {},
        clangd = {
          -- header-insertion=iwyu is already clangd's default; pinned here
          -- so it's documented. Only fires on completion accept, not for an
          -- identifier already typed - clangd has no code action for that.
          cmd = { "clangd", "--offset-encoding=utf-16", "--header-insertion=iwyu",
            "--background-index", "--clang-tidy", "--completion-style=detailed" },
        },
        helm_ls = {
          settings = {
            ["helm-ls"] = {
              yamlls = { path = "yaml-language-server" },
            },
          },
        },
        -- Dockerfile, docker-compose.yml/compose.yaml (see the
        -- "yaml.docker-compose" filetype in options.lua) and Bake files.
        docker_language_server = {},
        -- C#: Roslyn (mason package roslyn-language-server)
        roslyn_ls = {
          -- Older Mason `roslyn` installs provide the same executable name.
          mason = roslyn_needs_mason(),
          settings = {
            ["csharp|inlay_hints"] = {
              csharp_enable_inlay_hints_for_implicit_object_creation = true,
              csharp_enable_inlay_hints_for_implicit_variable_types = true,
              csharp_enable_inlay_hints_for_lambda_parameter_types = true,
              csharp_enable_inlay_hints_for_types = true,
              dotnet_enable_inlay_hints_for_indexer_parameters = true,
              dotnet_enable_inlay_hints_for_literal_parameters = true,
              dotnet_enable_inlay_hints_for_object_creation_parameters = true,
              dotnet_enable_inlay_hints_for_other_parameters = true,
              dotnet_enable_inlay_hints_for_parameters = true,
              dotnet_suppress_inlay_hints_for_parameters_that_differ_only_by_suffix = true,
              dotnet_suppress_inlay_hints_for_parameters_that_match_argument_name = true,
              dotnet_suppress_inlay_hints_for_parameters_that_match_method_intent = true,
            },
            ["csharp|code_lens"] = {
              dotnet_enable_references_code_lens = false,
              dotnet_enable_tests_code_lens = true,
            },
            ["csharp|completion"] = {
              dotnet_show_completion_items_from_unimported_namespaces = true,
              dotnet_show_name_completion_suggestions = true,
            },
            ["csharp|background_analysis"] = {
              dotnet_compiler_diagnostics_scope = "openFiles",
              dotnet_analyzer_diagnostics_scope = "openFiles",
            },
            ["csharp|symbol_search"] = {
              dotnet_search_reference_assemblies = true,
            },
          },
        },
        -- Mason-installed servers that LazyVim would otherwise auto-start next
        -- to the ones above (rustaceanvim runs rust-analyzer itself), which
        -- would duplicate every diagnostic
        rust_analyzer = { enabled = false },
        omnisharp = { enabled = false },
        csharp_ls = { enabled = false },
      },
    },
  },


  -- rustaceanvim: Rust LSP, inlay hints, macro expansion, codelldb DAP
  {
    "mrcjkb/rustaceanvim",
    keys = {
      { "<leader>rc", function()
        require("snacks").terminal.open({ "cargo", "clippy" }, { cwd = LazyVim.root(), auto_close = false })
      end, ft = "rust", desc = "Cargo Clippy" },
    },
    ft = { "rust" },
    config = function()
      vim.g.rustaceanvim = {
        server = {
          default_settings = {
            ["rust-analyzer"] = {
              check = { command = "check" },
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
