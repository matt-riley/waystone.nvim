-- plugin/waystone.lua
-- Auto-loaded by Neovim. Registers Waystone user commands.
--
-- Command parity with v1 keymaps:
--   WaystoneList        -> <leader>go  (open marks list)
--   WaystoneToggle      -> <leader>gT  (toggle marks list)
--   WaystoneScope       -> <leader>gs  (show scope info)
--   WaystoneSet N       -> set slot N to current location
--   WaystoneSelect N    -> jump to slot N
--   WaystoneToggleSlot N -> toggle slot N (set or clear)
--   WaystoneNext        -> cycle forward
--   WaystonePrev        -> cycle backward

local function ws()
  return require("waystone")
end

vim.api.nvim_create_user_command("WaystoneList", function()
  ws().open_list()
end, { desc = "Open waystone marks list" })

vim.api.nvim_create_user_command("WaystoneToggle", function()
  ws().toggle_list()
end, { desc = "Toggle waystone marks list" })

vim.api.nvim_create_user_command("WaystoneScope", function()
  ws().show_scope()
end, { desc = "Show waystone scope and mark count" })

vim.api.nvim_create_user_command("WaystoneSet", function(opts)
  local slot = tonumber(opts.args)
  if not slot then
    vim.notify("WaystoneSet: expected a slot number", vim.log.levels.ERROR)
    return
  end
  local _, err = ws().set(slot)
  if err then
    vim.notify("waystone: " .. err, vim.log.levels.ERROR)
  end
end, { nargs = 1, desc = "Save current location in slot N" })

vim.api.nvim_create_user_command("WaystoneSelect", function(opts)
  local slot = tonumber(opts.args)
  if not slot then
    vim.notify("WaystoneSelect: expected a slot number", vim.log.levels.ERROR)
    return
  end
  local _, err = ws().select(slot)
  if err then
    vim.notify("waystone: " .. err, vim.log.levels.WARN)
  end
end, { nargs = 1, desc = "Jump to waystone mark in slot N" })

vim.api.nvim_create_user_command("WaystoneToggleSlot", function(opts)
  local slot = tonumber(opts.args)
  if not slot then
    vim.notify("WaystoneToggleSlot: expected a slot number", vim.log.levels.ERROR)
    return
  end
  local _, err = ws().toggle(slot)
  if err then
    vim.notify("waystone: " .. err, vim.log.levels.WARN)
  end
end, { nargs = 1, desc = "Toggle waystone mark in slot N (set or clear)" })

vim.api.nvim_create_user_command("WaystoneNext", function()
  local _, err = ws().cycle_next()
  if err then
    vim.notify("waystone: " .. err, vim.log.levels.WARN)
  end
end, { desc = "Cycle to next waystone mark" })

vim.api.nvim_create_user_command("WaystonePrev", function()
  local _, err = ws().cycle_prev()
  if err then
    vim.notify("waystone: " .. err, vim.log.levels.WARN)
  end
end, { desc = "Cycle to previous waystone mark" })
