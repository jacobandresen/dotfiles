local function get_wezterm_scheme()
  local f = io.open(vim.fn.expand("~/.wezterm.lua"), "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return content:match('config%.color_scheme%s*=%s*"([^"]+)"')
end

local function wezterm_to_base16(scheme)
  if not scheme then return nil end
  local name = scheme:match("^(.-)%s*%(base16%)$") or scheme
  return "base16-" .. name:lower():gsub("%s+", "-")
end

local nvim_scheme = wezterm_to_base16(get_wezterm_scheme())

return {
  {
    "RRethy/nvim-base16",
    lazy = false,
    priority = 1000,
    enabled = nvim_scheme ~= nil,
    config = function()
      vim.cmd.colorscheme(nvim_scheme)
    end,
  },
  {
    "letorbi/vim-colors-modern-borland",
    lazy = false,
    priority = 999,
    enabled = nvim_scheme == nil,
    config = function()
      vim.g.BorlandStyle = "classic"
      vim.cmd.colorscheme("borland")
    end,
  },
  { "LazyVim/LazyVim", opts = { colorscheme = nvim_scheme or "borland" } },
}
