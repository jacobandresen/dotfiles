---
name: nvim-config
description: Edit and test the Neovim Lua configuration in ~/Projects/dotfiles/nvim. Use when modifying plugins, keymaps, LSP config, or any Lua file in the nvim dotfiles. Covers syntax checking, headless testing, and the project structure.
---

# Neovim Config

## Directory Structure

```
~/Projects/dotfiles/nvim/
├── init.lua                    # entry point
├── lua/
│   └── plugins/                # lazy.nvim plugin specs
│       ├── ai.lua              # AI/coding assistant plugins
│       ├── db.lua              # database tools (dadbod)
│       └── ...
└── dev/
    └── turbovim/
        └── lua/turbovim/       # custom tooling
```

## Before Editing

Check current syntax of the file you're about to change:

```bash
luac -p lua/plugins/FILENAME.lua
```

A clean exit (no output) means no syntax errors.

## Testing Changes

**Syntax check after editing:**
```bash
luac -p lua/plugins/FILENAME.lua && echo "syntax ok"
```

**Headless runtime test (runs Lua, exits):**
```bash
nvim --headless '+lua require("plugins.FILENAME")' +quit 2>&1
```

**Run the full init and check for errors:**
```bash
nvim --headless '+lua vim.cmd("checkhealth")' +quit 2>&1 | head -40
```

**Run existing tests (if Makefile target exists):**
```bash
make test
```

## Lazy.nvim Plugin Spec Pattern

```lua
return {
  "author/plugin-name",
  event = "VeryLazy",          -- or "BufReadPre", "InsertEnter", etc.
  dependencies = { "nvim-lua/plenary.nvim" },
  opts = {
    -- passed to plugin's setup()
  },
  config = function(_, opts)
    require("plugin-name").setup(opts)
    -- additional setup
  end,
  keys = {
    { "<leader>xx", "<cmd>PluginCmd<cr>", desc = "Do thing" },
  },
}
```

## Keymaps

Set keymaps in the plugin spec `keys` table (lazy-loaded) or in `config`:

```lua
vim.keymap.set("n", "<leader>xx", function()
  -- action
end, { desc = "description shown in which-key" })
```

Always include `desc` — which-key displays it.

## Common Issues

- **Plugin not loading**: check `event` trigger — use `lazy = false` to force eager load during debugging
- **Keymap conflict**: `:verbose map <leader>xx` shows what's bound and where
- **LSP not attaching**: `:LspInfo` and `:LspLog` are the first places to check
- **Syntax error in plugin file**: lazy.nvim skips the file silently — always run `luac -p` before restarting nvim
