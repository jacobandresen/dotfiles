-- classic `#include <SDL.h>` style needs an explicit -I into SDL2's include
-- dir; SDL3's `#include <SDL3/SDL.h>` already resolves via the default
-- include path. Only matters for ad-hoc files with no compile_commands.json.
local function clangd_fallback_flags()
  local extra = {}
  for _, dir in ipairs({ "/usr/include/SDL2", "/usr/local/include/SDL2", "/opt/homebrew/include/SDL2" }) do
    if vim.fn.isdirectory(dir) == 1 then
      table.insert(extra, "-I" .. dir)
      break
    end
  end
  return extra
end

-- SDL build & run: <leader>rr compiles the current C/C++ file against
-- whichever SDL major version (and companion libs) its #include lines
-- reference, then runs the resulting binary in a terminal split. Meant for
-- quick single-file experiments; real projects should use their own build
-- system and compile_commands.json instead.
local function sdl_run()
  local bufnr = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(bufnr)
  if file == "" then
    vim.notify("Save the file first", vim.log.levels.WARN)
    return
  end
  vim.cmd("write")

  local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  local function pc_exists(pkg)
    vim.fn.system({ "pkg-config", "--exists", pkg })
    return vim.v.shell_error == 0
  end

  local pkgs = {}
  if text:match("#include%s*<SDL3/") and pc_exists("sdl3") then
    table.insert(pkgs, "sdl3")
    for _, extra in ipairs({ "SDL3_image", "SDL3_ttf", "SDL3_mixer" }) do
      if text:match("#include%s*<" .. extra .. "/") and pc_exists(extra) then
        table.insert(pkgs, extra)
      end
    end
  elseif (text:match("#include%s*<SDL2/") or text:match("#include%s*<SDL%.h>")) and pc_exists("sdl2") then
    table.insert(pkgs, "sdl2")
    for _, extra in ipairs({ "SDL2_image", "SDL2_ttf", "SDL2_mixer" }) do
      if text:match("#include%s*<" .. extra .. "%.h>") and pc_exists(extra) then
        table.insert(pkgs, extra)
      end
    end
  end

  if #pkgs == 0 then
    vim.notify("No SDL #include found (or its pkg-config file is missing)", vim.log.levels.WARN)
    return
  end

  local function pc_flags(mode)
    local cmd = { "pkg-config", mode }
    vim.list_extend(cmd, pkgs)
    return vim.split(vim.trim(vim.fn.system(cmd)), "%s+", { trimempty = true })
  end

  local cxx = vim.bo[bufnr].filetype == "cpp"
  local compiler = cxx and "c++" or "cc"
  local out = vim.fn.tempname()
  local cmd = { compiler, "-std=" .. (cxx and "c++17" or "c11"), "-Wall", "-Wextra", "-g", file }
  vim.list_extend(cmd, pc_flags("--cflags"))
  vim.list_extend(cmd, { "-o", out })
  vim.list_extend(cmd, pc_flags("--libs"))

  local shell_cmd = table.concat(vim.tbl_map(vim.fn.shellescape, cmd), " ") .. " && " .. vim.fn.shellescape(out)
  require("snacks").terminal.open(shell_cmd, { win = { position = "bottom" } })
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "c", "cpp" },
  callback = function(args)
    vim.keymap.set("n", "<leader>rr", sdl_run, { buffer = args.buf, desc = "SDL: Build & Run" })
  end,
})

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
    opts = {
      ensure_installed = {
        "roslyn",
        "netcoredbg",
        "codelldb",
        "clangd",
        "js-debug-adapter",
        "rust-analyzer",
        "helm-ls",
        "prettier",
        "black",
        "isort",
        "clang-format",
        "goimports",
        "csharpier",
      },
      auto_update = false,
      run_on_start = true,
      integrations = {
        ["mason-lspconfig"] = false,
      },
    },
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
          init_options = {
            fallbackFlags = clangd_fallback_flags(),
          },
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
        callback = function()
          vim.bo.makeprg = "cargo"
        end,
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
