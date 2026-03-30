local M = {}

local uv = vim.uv or vim.loop

local state = {
  loaded = false,
  data = {
    version = 1,
    scopes = {},
  },
  config = {
    slots = 4,
    data_file = nil,
  },
  active_slot_by_scope = {},
}

local function data_file_path()
  if state.config.data_file and state.config.data_file ~= "" then
    return state.config.data_file
  end

  return vim.fs.joinpath(vim.fn.stdpath("data"), "waystone", "marks.json")
end

local function ensure_parent_dir(path)
  local dir = vim.fs.dirname(path)
  if not dir then
    return
  end

  vim.fn.mkdir(dir, "p")
end

local function encode_data()
  return vim.json.encode(state.data)
end

local function save_data()
  local path = data_file_path()
  ensure_parent_dir(path)

  local payload = encode_data()
  vim.fn.writefile({ payload }, path)
end

local function decode_data(raw)
  local ok, parsed = pcall(vim.json.decode, raw)
  if not ok or type(parsed) ~= "table" then
    return {
      version = 1,
      scopes = {},
    }
  end

  parsed.scopes = parsed.scopes or {}
  return parsed
end

local function load_data()
  if state.loaded then
    return
  end

  state.loaded = true

  local path = data_file_path()
  local stat = uv.fs_stat(path)
  if not stat then
    return
  end

  local lines = vim.fn.readfile(path)
  local raw = table.concat(lines, "\n")
  if raw == "" then
    return
  end

  state.data = decode_data(raw)
end

local function validate_slot(slot)
  if type(slot) ~= "number" or slot < 1 or slot ~= math.floor(slot) then
    return nil, "slot must be a positive integer"
  end

  if slot > state.config.slots then
    return nil, string.format("slot %d is out of range (max: %d)", slot, state.config.slots)
  end

  return true
end

local function normalize_mark(mark)
  if type(mark) ~= "table" then
    return nil, "mark must be a table"
  end

  if type(mark.path) ~= "string" or mark.path == "" then
    return nil, "mark.path must be a non-empty string"
  end

  if type(mark.row) ~= "number" or mark.row < 1 or mark.row ~= math.floor(mark.row) then
    return nil, "mark.row must be a positive integer"
  end

  if type(mark.col) ~= "number" or mark.col < 0 or mark.col ~= math.floor(mark.col) then
    return nil, "mark.col must be a non-negative integer"
  end

  return {
    path = mark.path,
    row = mark.row,
    col = mark.col,
  }
end

local function detect_scope_fallback(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  local start_dir = name ~= "" and vim.fs.dirname(name) or uv.cwd()

  if not start_dir or start_dir == "" then
    return nil
  end

  local git_dir = vim.fn.finddir(".git", start_dir .. ";")
  if git_dir == "" then
    return nil
  end

  return vim.fn.fnamemodify(git_dir, ":h")
end

function M.detect_scope(bufnr)
  bufnr = bufnr or 0

  if vim.fs and vim.fs.root then
    local ok, root = pcall(vim.fs.root, bufnr, ".git")
    if ok and type(root) == "string" and root ~= "" then
      return root
    end
  end

  return detect_scope_fallback(bufnr)
end

local function get_scope_key(scope)
  return scope or M.detect_scope(0)
end

local function get_scope_store(scope)
  local key = get_scope_key(scope)
  if not key then
    return nil
  end

  load_data()

  state.data.scopes[key] = state.data.scopes[key] or {}
  return key, state.data.scopes[key]
end

local function capture_current_mark()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    return nil, "current buffer has no file path"
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  return {
    path = path,
    row = cursor[1],
    col = cursor[2],
  }
end

function M.configure(config)
  state.config = vim.tbl_extend("force", state.config, config or {})
end

function M.data_path()
  return data_file_path()
end

function M.list_marks(scope)
  local key, scope_store = get_scope_store(scope)
  if not key then
    return {}
  end

  local marks = {}
  for slot = 1, state.config.slots do
    local mark = scope_store[tostring(slot)]
    if mark then
      marks[#marks + 1] = {
        slot = slot,
        mark = vim.deepcopy(mark),
      }
    end
  end

  return marks
end

function M.get_slot(slot, scope)
  local ok, err = validate_slot(slot)
  if not ok then
    return nil, err
  end

  local _, scope_store = get_scope_store(scope)
  if not scope_store then
    return nil, "no git root detected for current buffer"
  end

  local mark = scope_store[tostring(slot)]
  if not mark then
    return nil
  end

  return vim.deepcopy(mark)
end

function M.set_slot(slot, mark, scope)
  local ok, err = validate_slot(slot)
  if not ok then
    return nil, err
  end

  local _, scope_store = get_scope_store(scope)
  if not scope_store then
    return nil, "no git root detected for current buffer"
  end

  local value = mark
  if not value then
    local capture_err
    value, capture_err = capture_current_mark()
    if not value then
      return nil, capture_err or "unable to capture current mark"
    end
  end

  value, err = normalize_mark(value)
  if not value then
    return nil, err
  end

  scope_store[tostring(slot)] = value
  state.active_slot_by_scope[get_scope_key(scope)] = slot
  save_data()

  return vim.deepcopy(scope_store[tostring(slot)])
end

function M.clear_slot(slot, scope)
  local ok, err = validate_slot(slot)
  if not ok then
    return nil, err
  end

  local key, scope_store = get_scope_store(scope)
  if not scope_store then
    return nil, "no git root detected for current buffer"
  end

  scope_store[tostring(slot)] = nil
  if state.active_slot_by_scope[key] == slot then
    state.active_slot_by_scope[key] = nil
  end

  save_data()
  return true
end

function M.toggle_slot(slot, scope)
  local mark, err = M.get_slot(slot, scope)
  if err then
    return nil, err
  end

  local current, current_err = capture_current_mark()
  if not current then
    return nil, current_err
  end

  if mark and mark.path == current.path and mark.row == current.row and mark.col == current.col then
    local cleared, clear_err = M.clear_slot(slot, scope)
    if not cleared then
      return nil, clear_err
    end

    return true, "cleared"
  end

  local saved, save_err = M.set_slot(slot, current, scope)
  if not saved then
    return nil, save_err
  end

  return saved, "set"
end

function M.select_slot(slot, scope)
  local mark, err = M.get_slot(slot, scope)
  if err then
    return nil, err
  end
  if not mark then
    return nil, string.format("slot %d is empty", slot)
  end

  local escaped = vim.fn.fnameescape(mark.path)
  vim.cmd.edit(escaped)
  vim.api.nvim_win_set_cursor(0, { mark.row, mark.col })

  local key = get_scope_key(scope)
  if key then
    state.active_slot_by_scope[key] = slot
  end

  return vim.deepcopy(mark)
end

function M.cycle(step, scope)
  step = step or 1
  local key = get_scope_key(scope)
  if not key then
    return nil, "no git root detected for current buffer"
  end

  local marks = M.list_marks(key)
  if #marks == 0 then
    return nil, "no marks set for this scope"
  end

  local current_slot = state.active_slot_by_scope[key]
  local idx

  if current_slot then
    idx = 1
    for i, entry in ipairs(marks) do
      if entry.slot == current_slot then
        idx = i
        break
      end
    end
    if step > 0 then
      idx = (idx % #marks) + 1
    elseif step < 0 then
      idx = ((idx - 2 + #marks) % #marks) + 1
    end
  else
    idx = step < 0 and #marks or 1
  end

  local next_entry = marks[idx]
  local selected, err = M.select_slot(next_entry.slot, key)
  if not selected then
    return nil, err
  end

  return {
    slot = next_entry.slot,
    mark = selected,
  }
end

function M.reset_for_tests()
  state.loaded = false
  state.data = {
    version = 1,
    scopes = {},
  }
  state.active_slot_by_scope = {}
end

return M
