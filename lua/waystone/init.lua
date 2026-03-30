-- lua/waystone/init.lua
local M = {}

--- waystone.nvim
---
--- Navigate your Neovim project like a fantasy hero — drop waystones to mark
--- locations and jump between them instantly.
---
---@tag waystone

--- Plugin configuration.
---@class waystone.Config

---@private
local defaults = {}

---@private
---@type waystone.Config
M.config = vim.deepcopy(defaults)

--- Configure the plugin with user options.
---
--- Call this once in your Neovim config to override defaults.
---
---@param opts? waystone.Config User configuration options
function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
end

return M
