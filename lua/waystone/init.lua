-- lua/waystone/init.lua
local waystone = {}

local core = require("waystone.core")
local ui = require("waystone.ui")

--- waystone.nvim
---
--- Slot-based project marks for Neovim.
---
--- Marks are persisted in JSON and grouped by git-root scope. The current v1
--- implementation is intentionally small: save marks into numbered slots, jump
--- back to them later, cycle between populated slots, and inspect them through
--- a lightweight floating list.
---
--- Commands ~
--- - `:WaystoneList` opens the floating marks list.
--- - `:WaystoneToggle` toggles the marks list window.
--- - `:WaystoneScope` shows the active scope and mark count.
--- - `:WaystoneSet {slot}` saves the current cursor location into a slot.
--- - `:WaystoneSelect {slot}` jumps to a slot.
--- - `:WaystoneToggleSlot {slot}` toggles a slot on the current cursor
---   location.
--- - `:WaystoneNext` / `:WaystonePrev` cycle between populated slots.
---
---@tag waystone

--- Plugin configuration.
---@class waystone.Config
---@field slots? integer Number of slot-oriented marks stored per scope. Default: 4.
---@field data_file? string Optional override for the JSON persistence file.

--- Persisted cursor location.
---@class waystone.Mark
---@field path string Absolute file path for the mark.
---@field row integer 1-based cursor row.
---@field col integer 0-based cursor column.

--- Slot-oriented mark entry returned by listing/cycling helpers.
---@class waystone.SlotEntry
---@field slot integer Slot number.
---@field mark waystone.Mark Mark saved in this slot.

---@private
local defaults = {
  slots = 4,
  data_file = nil,
}

--- Active plugin configuration.
---
--- Default values:
--- - `slots = 4`
--- - `data_file = nil`
---@type waystone.Config
waystone.config = vim.deepcopy(defaults)

--- Configure the plugin with user options.
---
--- Call this once in your Neovim config to override defaults.
---
---@usage >lua
---   require("waystone").setup()
---   -- OR
---   require("waystone").setup({
---     slots = 6,
---   })
--- <
---
---@param opts? waystone.Config User configuration options
function waystone.setup(opts)
  opts = opts or {}
  waystone.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
  core.configure(waystone.config)
end

--- Detect the git-root scope used by API calls when `scope` is omitted.
---@return string|nil scope Absolute path of the detected git root.
function waystone.detect_scope()
  return core.detect_scope(0)
end

--- List populated marks for a scope ordered by slot number.
---@param scope? string Optional explicit scope. Defaults to the current buffer's git root.
---@return waystone.SlotEntry[]
function waystone.list(scope)
  return core.list_marks(scope)
end

--- Save a mark into a slot.
---
--- If `mark` is omitted, the current buffer path and cursor position are used.
--- Saving a mark also makes that slot the active navigation target for future
--- calls to |waystone.cycle_next()| and |waystone.cycle_prev()|.
---
---@param slot integer Slot number to update.
---@param mark? waystone.Mark Explicit mark value. Omit to capture the current cursor location.
---@param scope? string Optional explicit scope. Defaults to the current buffer's git root.
---@return waystone.Mark|nil mark Saved mark.
---@return string? err Error message on failure.
function waystone.set(slot, mark, scope)
  return core.set_slot(slot, mark, scope)
end

--- Clear a slot in a scope.
---
--- Clearing the currently active slot resets cycle state for that scope.
---
---@param slot integer Slot number to clear.
---@param scope? string Optional explicit scope. Defaults to the current buffer's git root.
---@return boolean|nil ok `true` when the slot was cleared.
---@return string? err Error message on failure.
function waystone.clear(slot, scope)
  return core.clear_slot(slot, scope)
end

--- Toggle a slot using the current cursor location.
---
--- If the slot already points at the current file/row/column, it is cleared.
--- Otherwise the current cursor location is stored in that slot.
---
---@param slot integer Slot number to toggle.
---@param scope? string Optional explicit scope. Defaults to the current buffer's git root.
---@return waystone.Mark|boolean|nil result Saved mark when set, `true` when cleared.
---@return string? status Status string (`"set"` / `"cleared"`) or an error message.
function waystone.toggle(slot, scope)
  return core.toggle_slot(slot, scope)
end

--- Jump to a slot mark.
---
--- This opens the marked file with `:edit`, moves the cursor, and remembers the
--- selected slot as the current position for cycling.
---
---@param slot integer Slot number to jump to.
---@param scope? string Optional explicit scope. Defaults to the current buffer's git root.
---@return waystone.Mark|nil mark Selected mark.
---@return string? err Error message on failure.
function waystone.select(slot, scope)
  return core.select_slot(slot, scope)
end

--- Cycle forward across populated slots.
---
--- Only populated slots are visited. If no slot is currently active for the
--- scope, cycling forward starts from the first populated slot.
---
---@param scope? string Optional explicit scope. Defaults to the current buffer's git root.
---@return waystone.SlotEntry|nil entry Selected slot entry.
---@return string? err Error message on failure.
function waystone.cycle_next(scope)
  return core.cycle(1, scope)
end

--- Cycle backward across populated slots.
---
--- Only populated slots are visited. If no slot is currently active for the
--- scope, cycling backward starts from the last populated slot.
---
---@param scope? string Optional explicit scope. Defaults to the current buffer's git root.
---@return waystone.SlotEntry|nil entry Selected slot entry.
---@return string? err Error message on failure.
function waystone.cycle_prev(scope)
  return core.cycle(-1, scope)
end

--- Return the resolved persistence file path.
---@return string path JSON file used for storing marks.
function waystone.data_path()
  return core.data_path()
end

--- Open the floating marks list for a scope.
---@param scope? string Optional explicit scope. Defaults to the current buffer's git root.
function waystone.open_list(scope)
  ui.open_list(scope)
end

--- Toggle the floating marks list for a scope.
---@param scope? string Optional explicit scope. Defaults to the current buffer's git root.
function waystone.toggle_list(scope)
  ui.toggle_list(scope)
end

--- Show the active scope and mark count.
---@param scope? string Optional explicit scope. Defaults to the current buffer's git root.
function waystone.show_scope(scope)
  ui.show_scope(scope)
end

--- Toggle a file-level mark for the current buffer.
---
--- If the current file is already marked in any slot for the scope, that slot
--- is cleared. Otherwise the current cursor location is stored in the lowest
--- available slot.
---
---@param scope? string Optional explicit scope. Defaults to the current buffer's git root.
---@return waystone.Mark|boolean|nil result Saved mark when set, `true` when cleared.
---@return string? err Status string (`"set"` / `"cleared"`) or an error message.
function waystone.toggle_file(scope)
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    return nil, "current buffer has no file path"
  end

  local marks = core.list_marks(scope)
  for _, entry in ipairs(marks) do
    if entry.mark.path == path then
      local ok, err = core.clear_slot(entry.slot, scope)
      if not ok then
        return nil, err
      end
      return true, "cleared"
    end
  end

  local used = {}
  for _, entry in ipairs(marks) do
    used[entry.slot] = true
  end

  local max_slots = waystone.config and waystone.config.slots or 4
  for s = 1, max_slots do
    if not used[s] then
      local mark, err = core.set_slot(s, nil, scope)
      if not mark then
        return nil, err
      end
      return mark, "set"
    end
  end

  return nil, string.format("all %d slots are already populated", max_slots)
end

return waystone
