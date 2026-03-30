-- lua/waystone/ui.lua
-- Minimal floating-window UI for waystone marks list and scope info.
local M = {}

local core = require("waystone.core")

local list_state = { win = nil, buf = nil }

local function is_list_open()
  return list_state.win ~= nil and vim.api.nvim_win_is_valid(list_state.win)
end

local function close_list()
  if is_list_open() then
    vim.api.nvim_win_close(list_state.win, true)
  end
  list_state.win = nil
  list_state.buf = nil
end

local function build_lines(marks)
  if #marks == 0 then
    return { "  (no marks set for this scope)" }, {}
  end

  local lines = {}
  local slots = {}
  for _, entry in ipairs(marks) do
    local rel = vim.fn.fnamemodify(entry.mark.path, ":~:.")
    lines[#lines + 1] = string.format("  [%d]  %s  %d:%d", entry.slot, rel, entry.mark.row, entry.mark.col)
    slots[#slots + 1] = entry.slot
  end
  return lines, slots
end

local function open_list(scope)
  scope = scope or core.detect_scope(0)
  local marks = core.list_marks(scope)
  local lines, slots = build_lines(marks)

  local ui = vim.api.nvim_list_uis()[1] or { width = 80, height = 24 }
  local width = math.min(70, ui.width - 4)
  local height = math.max(#lines, 1)
  local row = math.floor((ui.height - height) / 2)
  local col = math.floor((ui.width - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("filetype", "waystone-list", { buf = buf })

  local win_config = {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
  }

  -- title support added in Neovim 0.9
  if vim.fn.has("nvim-0.9") == 1 then
    win_config.title = " Waystone Marks "
    win_config.title_pos = "center"
  end

  local win = vim.api.nvim_open_win(buf, true, win_config)
  list_state.win = win
  list_state.buf = buf

  -- Clear state when the window is closed externally (e.g. :q, WinClosed)
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      list_state.win = nil
      list_state.buf = nil
    end,
  })

  local function map(key, fn)
    vim.keymap.set("n", key, fn, { buffer = buf, nowait = true, silent = true })
  end

  map("<CR>", function()
    local lnum = vim.api.nvim_win_get_cursor(win)[1]
    local slot = slots[lnum]
    close_list()
    if slot then
      core.select_slot(slot, scope)
    end
  end)

  map("d", function()
    local lnum = vim.api.nvim_win_get_cursor(win)[1]
    local slot = slots[lnum]
    if slot then
      core.clear_slot(slot, scope)
      close_list()
      open_list(scope)
    end
  end)

  map("q", close_list)
  map("<Esc>", close_list)
end

--- Open the marks list window for the current scope.
---@param scope? string
function M.open_list(scope)
  if is_list_open() then
    close_list()
  end
  open_list(scope)
end

--- Toggle the marks list window open or closed.
---@param scope? string
function M.toggle_list(scope)
  if is_list_open() then
    close_list()
  else
    open_list(scope)
  end
end

--- Echo lightweight scope and mark-count info for the active scope.
---@param scope? string
---@param slots? integer
function M.show_scope(scope, slots)
  local detected = scope or core.detect_scope(0)
  if not detected then
    vim.notify("waystone: no git-root scope detected", vim.log.levels.WARN)
    return
  end

  local marks = core.list_marks(detected)
  local rel = vim.fn.fnamemodify(detected, ":~:.")
  local count = #marks
  local max_slots = slots or "?"
  local msg = string.format("scope: %s  |  marks: %d / %s", rel, count, max_slots)

  vim.notify(msg, vim.log.levels.INFO, { title = "Waystone" })
end

return M
