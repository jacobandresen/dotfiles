-- theme_manager.lua
local M = {}

-- NOTE: In a real system, the paths need to correctly reflect where the 
-- configuration files are stored relative to the execution context. 
-- Using stdpath based logic for Neovim context.
local CONFIG_PATH = vim.fn.expand('~/.local/share/nvim/lua/my_theme_switcher/config_themes.lua')

--- Lists all available theme names found in the specified directory. 
--- Replicates the theme discovery part of the original shell script.
--- @return A table of theme names (strings).
function M.get_available_themes()
    -- HARDCODED SIMULATION: Replace this entire block with actual file system reading 
    -- if you are reading from a physical 'themes' directory.
    print("--- Available Themes Simulated ---")
    local themes = {}
    table.insert(themes, "onedark")
    table.insert(themes, "catppuccin")
    table.insert(themes, "solarized")
    table.insert(themes, "default")
    print("Themes found: " .. table.concat(themes, ", "))
    return themes
end

--- Sets the Neovim color scheme/theme by writing the appropriate command 
--- to the designated configuration file location.
--- This function relies on the calling environment to reload or execute the modified config.
--- @param theme_name string The name of the theme to apply.
return M
