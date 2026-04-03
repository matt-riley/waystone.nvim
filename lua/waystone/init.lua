-- lua/waystone/init.lua
local waystone = {}

local core = require("waystone.core")
local ui = require("waystone.ui")

--- waystone.nvim
---
--- Slot-based project marks for Neovim.
---
--- Marks are persisted in JSON and grouped by a resolved scope key. The default
--- scope remains the current git root, but built-in scope modes can also use
--- the current working directory, a stable global scope, or a git-branch scope.
--- The implementation stays intentionally small: save marks into numbered
--- slots, jump back to them later, cycle between populated slots, inspect them
--- through a lightweight floating list, and export them to quickfix when
--- needed.
---
--- Commands ~
--- - `:WaystoneList` opens the floating marks list.
--- - `:WaystoneToggle` toggles the marks list window.
--- - `:WaystoneScope` shows the active scope and mark count.
--- - `:WaystoneQuickfix` exports the current scope to quickfix and opens it.
--- - `:WaystoneClearAll` clears all populated slots in the current scope.
--- - `:WaystoneSet {slot}` saves the current cursor location into a slot.
--- - `:WaystoneSelect {slot}` jumps to a slot.
--- - `:WaystoneToggleSlot {slot}` toggles a slot on the current cursor
---   location.
--- - `:WaystoneNext` / `:WaystonePrev` cycle between populated slots.
---
--- List window mappings ~
--- - `<CR>` opens the slot under the cursor.
--- - `d` clears the slot under the cursor.
--- - `1`-`9` jump directly to visible slots.
--- - `<C-s>` opens the selected slot in a horizontal split.
--- - `|` opens the selected slot in a vertical split.
--- - `<C-q>` exports the current scope to quickfix.
--- - `q` / `<Esc>` close the list.
---
---@tag waystone

--- Plugin configuration.
---@class waystone.Config
---@field slots? integer Number of slot-oriented marks stored per scope. Default: 4.
---@field data_file? string Optional override for the JSON persistence file.
---@field scope_mode? '"git"'|'"cwd"'|'"global"'|'"git_branch"' Built-in default scope resolver. Default: "git".

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
  scope_mode = "git",
}

--- Active plugin configuration.
---
--- Default values:
--- - `slots = 4`
--- - `data_file = nil`
--- - `scope_mode = "git"`
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
---     scope_mode = "git_branch",
---   })
--- <
---
---@param opts? waystone.Config User configuration options
function waystone.setup(opts)
  opts = opts or {}
  vim.validate({
    scope_mode = {
      opts.scope_mode,
      function(value)
        return value == nil or vim.tbl_contains({ "git", "cwd", "global", "git_branch" }, value)
      end,
      'one of "git", "cwd", "global", "git_branch"',
    },
  })
  waystone.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
  core.configure(waystone.config)
end

--- Detect the resolved default scope used by API calls when `scope` is omitted.
---@return string|nil scope Resolved scope key for the current buffer/config.
function waystone.detect_scope()
  return core.detect_scope(0)
end

--- List populated marks for a scope ordered by slot number.
---@param scope? string Optional explicit scope. Defaults to the configured scope mode.
---@return waystone.SlotEntry[]
function waystone.list(scope)
  return core.list_marks(scope)
end

--- Return the slot assigned to a file within a scope.
---
--- If `path` is omitted, the current buffer path is used.
---
---@param path? string Optional file path. Defaults to the current buffer path.
---@param scope? string Optional explicit scope. Defaults to the configured scope mode.
---@return integer|nil slot Slot containing the file mark.
---@return string? err Error message on failure.
function waystone.slot_for_file(path, scope)
  return core.find_slot_by_path(path, scope)
end

--- Return whether a file is marked within a scope.
---
--- If `path` is omitted, the current buffer path is used.
---
---@param path? string Optional file path. Defaults to the current buffer path.
---@param scope? string Optional explicit scope. Defaults to the configured scope mode.
---@return boolean|nil exists `true` when the file is marked in the scope.
---@return string? err Error message on failure.
function waystone.exists(path, scope)
  return core.exists(path, scope)
end

--- Return the active slot currently tracked for cycling in a scope.
---@param scope? string Optional explicit scope. Defaults to the configured scope mode.
---@return integer|nil slot Active slot for the scope.
---@return string? err Error message on failure.
function waystone.current_slot(scope)
  return core.current_slot(scope)
end

--- Save a mark into a slot.
---
--- If `mark` is omitted, the current buffer path and cursor position are used.
--- Saving a mark also makes that slot the active navigation target for future
--- calls to |waystone.cycle_next()| and |waystone.cycle_prev()|.
---
---@param slot integer Slot number to update.
---@param mark? waystone.Mark Explicit mark value. Omit to capture the current cursor location.
---@param scope? string Optional explicit scope. Defaults to the configured scope mode.
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
---@param scope? string Optional explicit scope. Defaults to the configured scope mode.
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
---@param scope? string Optional explicit scope. Defaults to the configured scope mode.
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
---@param scope? string Optional explicit scope. Defaults to the configured scope mode.
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
---@param scope? string Optional explicit scope. Defaults to the configured scope mode.
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
---@param scope? string Optional explicit scope. Defaults to the configured scope mode.
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

--- Export scope marks to the quickfix list in slot order.
---@param scope? string Optional explicit scope. Defaults to the configured scope mode.
---@return integer|nil count Number of quickfix entries created.
---@return string? err Error message on failure.
function waystone.quickfix(scope)
  return core.quickfix(scope)
end

--- Clear all populated slots for a scope.
---@param scope? string Optional explicit scope. Defaults to the configured scope mode.
---@return integer|nil count Number of cleared marks.
---@return string? err Error message on failure.
function waystone.clear_all(scope)
  return core.clear_all(scope)
end

--- Open the floating marks list for a scope.
---
--- Inside the list window:
--- - `<CR>` opens the current slot
--- - `d` clears the current slot
--- - `1`-`9` jump to visible slots
--- - `<C-s>` opens the slot in a horizontal split
--- - `|` opens the slot in a vertical split
--- - `<C-q>` exports the scope to quickfix
--- - `q` / `<Esc>` close the window
---@param scope? string Optional explicit scope. Defaults to the configured scope mode.
function waystone.open_list(scope)
  ui.open_list(scope)
end

--- Toggle the floating marks list for a scope.
---@param scope? string Optional explicit scope. Defaults to the configured scope mode.
function waystone.toggle_list(scope)
  ui.toggle_list(scope)
end

--- Show the active scope and mark count.
---@param scope? string Optional explicit scope. Defaults to the configured scope mode.
function waystone.show_scope(scope)
  ui.show_scope(scope, waystone.config.slots)
end

--- Toggle a file-level mark for the current buffer.
---
--- If the current file is already marked in any slot for the scope, that slot
--- is cleared. Otherwise the current cursor location is stored in the lowest
--- available slot.
---
---@param scope? string Optional explicit scope. Defaults to the configured scope mode.
---@return waystone.Mark|boolean|nil result Saved mark when set, `true` when cleared.
---@return string? err Status string (`"set"` / `"cleared"`) or an error message.
function waystone.toggle_file(scope)
  return core.toggle_file(scope)
end

return waystone
