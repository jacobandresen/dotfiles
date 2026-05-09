return {
  -- mason: add roslyn registry
  {
    "mason-org/mason.nvim",
    opts = {
      registries = {
        "github:mason-org/mason-registry",
        "github:Crashdummyy/mason-registry",
      },
    },
  },

  -- ensure tools are installed
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "mason-org/mason.nvim" },
    config = function()
      require("mason-tool-installer").setup({
        ensure_installed = { "roslyn", "netcoredbg", "codelldb", "clangd", "js-debug-adapter" },
        auto_update = false,
        run_on_start = true,
        integrations = {
          ["mason-lspconfig"] = false,
        },
      })
    end,
  },

  -- helm syntax
  { "towolf/vim-helm", ft = "helm" },

  -- helm LSP config
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        clangd = {
          cmd = { "clangd", "--offset-encoding=utf-16" },
        },
        helm_ls = {
          settings = {
            ["helm-ls"] = {
              yamlls = { path = "yaml-language-server" },
            },
          },
        },
      },
    },
  },

  -- C# via Roslyn LSP
  {
    "seblj/roslyn.nvim",
    ft = "cs",
    opts = {
      silent = true,
      config = {
        on_attach = function(client, bufnr)
          -- keep client aware of semantic token capability
          client.server_capabilities = vim.tbl_deep_extend("force", client.server_capabilities, {
            semanticTokensProvider = { full = true },
          })

          -- roslyn only supports range semantic tokens; patch full→range requests
          local original_request = client.request
          client.request = function(method, params, handler, ctx, config)
            if method == "textDocument/semanticTokens/full" then
              local target_bufnr = vim.uri_to_bufnr(params.textDocument.uri)
              if not vim.api.nvim_buf_is_loaded(target_bufnr) then
                vim.notify("[LSP] Buffer not loaded: " .. params.textDocument.uri, vim.log.levels.WARN)
                return original_request(method, params, handler, ctx, config)
              end
              local line_count = vim.api.nvim_buf_line_count(target_bufnr)
              local last_line = vim.api.nvim_buf_get_lines(target_bufnr, line_count - 1, line_count, true)[1] or ""
              local new_params = {
                textDocument = params.textDocument,
                range = {
                  start = { line = 0, character = 0 },
                  ["end"] = { line = line_count - 1, character = #last_line },
                },
              }
              return original_request("textDocument/semanticTokens/range", new_params, handler, ctx, config)
            end
            return original_request(method, params, handler, ctx, config)
          end
        end,
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
            dotnet_enable_references_code_lens = true,
            dotnet_enable_tests_code_lens = true,
          },
          ["csharp|completion"] = {
            dotnet_show_completion_items_from_unimported_namespaces = true,
            dotnet_show_name_completion_suggestions = true,
          },
          ["csharp|background_analysis"] = {
            background_analysis_dotnet_compiler_diagnostics_scope = "fullSolution",
          },
          ["csharp|symbol_search"] = {
            dotnet_search_reference_assemblies = true,
          },
        },
      },
    },
  },
}
