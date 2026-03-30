-- plugin/waystone.lua
-- Auto-loaded by Neovim. Registers the :Waystone user command.

vim.api.nvim_create_user_command("Waystone", function()
  vim.notify("waystone.nvim: not yet implemented", vim.log.levels.INFO)
end, { desc = "Run waystone" })
