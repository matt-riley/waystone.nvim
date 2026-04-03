local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local waystone = require("waystone")
local core = require("waystone.core")
local MISSING = {}

local function with_notify_spy(fn)
  local original_notify = vim.notify
  local notifications = {}

  vim.notify = function(msg, level, opts)
    notifications[#notifications + 1] = {
      msg = msg,
      level = level,
      opts = opts,
    }
  end

  local ok, err = pcall(fn, notifications)
  vim.notify = original_notify

  if not ok then
    error(err, 0)
  end
end

local function with_overrides(target, replacements, fn)
  local originals = {}
  for key, value in pairs(replacements) do
    if target[key] == nil then
      originals[key] = MISSING
    else
      originals[key] = target[key]
    end
    target[key] = value
  end

  local ok, err = pcall(fn)

  for key, value in pairs(originals) do
    if value == MISSING then
      target[key] = nil
    else
      target[key] = value
    end
  end

  if not ok then
    error(err, 0)
  end
end

local function with_temp_data_file(fn)
  local data_file = vim.fs.joinpath(vim.fn.getcwd(), "tests", ".tmp-waystone-data.json")
  vim.fn.delete(data_file)

  waystone.setup({ data_file = data_file })
  core.reset_for_tests()

  local ok, err = pcall(fn, data_file)

  vim.fn.delete(data_file)

  if not ok then
    error(err, 0)
  end
end

local function with_temp_files(files, fn)
  for path, lines in pairs(files) do
    vim.fn.writefile(lines, path)
  end

  local ok, err = pcall(fn)

  for path in pairs(files) do
    vim.fn.delete(path)
  end

  if not ok then
    error(err, 0)
  end
end

local function edit_at(path, row, col)
  vim.cmd.edit(vim.fn.fnameescape(path))
  vim.api.nvim_win_set_cursor(0, { row, col })
end

local function current_git_branch_scope()
  local root = vim.fn.getcwd()
  local result = vim.fn.system({ "git", "-C", root, "symbolic-ref", "--short", "HEAD" })
  local branch = vim.trim(result)
  if vim.v.shell_error ~= 0 or branch == "" or branch == "HEAD" then
    return root
  end

  return string.format("%s:%s", root, branch)
end

local setup_set = MiniTest.new_set({
  hooks = {
    pre_case = function()
      waystone.setup()
      core.reset_for_tests()
    end,
  },
})

setup_set["setup() initialises with default config"] = function()
  MiniTest.expect.equality(waystone.config.slots, 4)
end

setup_set["setup() merges user options"] = function()
  waystone.setup({ slots = 6, scope_mode = "global" })
  MiniTest.expect.equality(waystone.config.slots, 6)
  MiniTest.expect.equality(waystone.config.scope_mode, "global")
end

T["setup"] = setup_set

local core_set = MiniTest.new_set()

core_set["set/list/clear manage slot-ordered marks"] = function()
  with_temp_data_file(function(data_file)
    local scope = vim.fn.getcwd()
    local fixture_a = vim.fs.joinpath(scope, "tests", "fixture-a.lua")
    local fixture_b = vim.fs.joinpath(scope, "tests", "fixture-b.lua")

    local mark2, err2 = waystone.set(2, { path = fixture_b, row = 12, col = 3 }, scope)
    MiniTest.expect.no_error(function()
      assert(mark2 and not err2)
    end)

    local mark1, err1 = waystone.set(1, { path = fixture_a, row = 4, col = 1 }, scope)
    MiniTest.expect.no_error(function()
      assert(mark1 and not err1)
    end)

    local listed = waystone.list(scope)
    MiniTest.expect.equality(#listed, 2)
    MiniTest.expect.equality(listed[1].slot, 1)
    MiniTest.expect.equality(listed[2].slot, 2)

    local removed, remove_err = waystone.clear(1, scope)
    MiniTest.expect.no_error(function()
      assert(removed and not remove_err)
    end)

    local after_clear = waystone.list(scope)
    MiniTest.expect.equality(#after_clear, 1)
    MiniTest.expect.equality(after_clear[1].slot, 2)

    MiniTest.expect.equality(vim.fn.filereadable(data_file), 1)
  end)
end

core_set["detect_scope prefers git root"] = function()
  local scope = waystone.detect_scope()
  MiniTest.expect.equality(scope, vim.fn.getcwd())
end

core_set["detect_scope supports cwd and global scope modes"] = function()
  waystone.setup({ scope_mode = "cwd" })
  MiniTest.expect.equality(waystone.detect_scope(), vim.fn.getcwd())

  waystone.setup({ scope_mode = "global" })
  MiniTest.expect.equality(waystone.detect_scope(), "global")
end

core_set["detect_scope supports git_branch mode"] = function()
  waystone.setup({ scope_mode = "git_branch" })
  MiniTest.expect.equality(waystone.detect_scope(), current_git_branch_scope())
end

core_set["explicit scope overrides configured scope mode"] = function()
  with_temp_data_file(function()
    waystone.setup({ scope_mode = "global" })
    core.reset_for_tests()

    local explicit_scope = vim.fs.joinpath(vim.fn.getcwd(), "tests", "custom-scope")
    local fixture = vim.fs.joinpath(vim.fn.getcwd(), "tests", "fixture-explicit.lua")

    local saved, err = waystone.set(1, { path = fixture, row = 7, col = 2 }, explicit_scope)
    MiniTest.expect.no_error(function()
      assert(saved and not err)
    end)

    MiniTest.expect.equality(waystone.list(), {})
    MiniTest.expect.equality(waystone.list(explicit_scope), {
      {
        slot = 1,
        mark = { path = fixture, row = 7, col = 2 },
      },
    })
  end)
end

core_set["slot validation errors on out-of-range slots"] = function()
  with_temp_data_file(function()
    local _, err = waystone.set(99, { path = "x", row = 1, col = 0 }, vim.fn.getcwd())
    MiniTest.expect.equality(type(err), "string")
  end)
end

core_set["toggle() captures cursor state and clears matching marks"] = function()
  with_temp_data_file(function()
    local scope = vim.fn.getcwd()
    local path = vim.fs.joinpath(scope, "tests", ".tmp-toggle.lua")

    with_temp_files({
      [path] = {
        "local toggle_target = true",
        "",
        "return toggle_target",
      },
    }, function()
      edit_at(path, 1, 6)

      local saved, status = waystone.toggle(1, scope)
      MiniTest.expect.equality(status, "set")
      MiniTest.expect.equality(saved, {
        path = path,
        row = 1,
        col = 6,
      })

      local listed = waystone.list(scope)
      MiniTest.expect.equality(#listed, 1)
      MiniTest.expect.equality(listed[1], {
        slot = 1,
        mark = saved,
      })

      edit_at(path, 1, 6)

      local cleared, clear_status = waystone.toggle(1, scope)
      MiniTest.expect.equality(cleared, true)
      MiniTest.expect.equality(clear_status, "cleared")
      MiniTest.expect.equality(waystone.list(scope), {})
    end)
  end)
end

core_set["toggle_file() uses the lowest free slot and clears an existing file mark"] = function()
  with_temp_data_file(function()
    local scope = vim.fn.getcwd()
    local path = vim.fs.joinpath(scope, "tests", ".tmp-toggle-file.lua")

    with_temp_files({
      [path] = {
        "local toggle_file_target = true",
        "",
        "return toggle_file_target",
      },
    }, function()
      edit_at(path, 2, 0)

      local saved, status = waystone.toggle_file(scope)
      MiniTest.expect.equality(status, "set")
      MiniTest.expect.equality(saved, {
        path = path,
        row = 2,
        col = 0,
      })
      MiniTest.expect.equality(waystone.list(scope)[1].slot, 1)

      local cleared, clear_status = waystone.toggle_file(scope)
      MiniTest.expect.equality(cleared, true)
      MiniTest.expect.equality(clear_status, "cleared")
      MiniTest.expect.equality(waystone.list(scope), {})
    end)
  end)
end

core_set["select() and cycle_*() navigate populated slots in order"] = function()
  with_temp_data_file(function(data_file)
    local scope = vim.fn.getcwd()
    local path_a = vim.fs.joinpath(scope, "tests", ".tmp-cycle-a.lua")
    local path_b = vim.fs.joinpath(scope, "tests", ".tmp-cycle-b.lua")

    with_temp_files({
      [path_a] = { "local first = true", "return first" },
      [path_b] = { "local second = true", "", "return second" },
    }, function()
      waystone.set(2, { path = path_a, row = 2, col = 3 }, scope)
      waystone.set(4, { path = path_b, row = 3, col = 1 }, scope)
      core.reset_for_tests()
      waystone.setup({ data_file = data_file })

      local backward = waystone.cycle_prev(scope)
      MiniTest.expect.equality(backward, {
        slot = 4,
        mark = { path = path_b, row = 3, col = 1 },
      })
      MiniTest.expect.equality(vim.api.nvim_buf_get_name(0), path_b)
      MiniTest.expect.equality(vim.api.nvim_win_get_cursor(0), { 3, 1 })

      local forward = waystone.cycle_next(scope)
      MiniTest.expect.equality(forward, {
        slot = 2,
        mark = { path = path_a, row = 2, col = 3 },
      })
      MiniTest.expect.equality(vim.api.nvim_buf_get_name(0), path_a)
      MiniTest.expect.equality(vim.api.nvim_win_get_cursor(0), { 2, 3 })

      local selected = waystone.select(4, scope)
      MiniTest.expect.equality(selected, { path = path_b, row = 3, col = 1 })

      local wrapped = waystone.cycle_next(scope)
      MiniTest.expect.equality(wrapped, {
        slot = 2,
        mark = { path = path_a, row = 2, col = 3 },
      })
    end)
  end)
end

core_set["cycle state is tracked independently per scope"] = function()
  with_temp_data_file(function()
    local cwd = vim.fn.getcwd()
    local scope_a = vim.fs.joinpath(cwd, "scope-a")
    local scope_b = vim.fs.joinpath(cwd, "scope-b")
    local path_a = vim.fs.joinpath(cwd, "tests", ".tmp-scope-a.lua")
    local path_b = vim.fs.joinpath(cwd, "tests", ".tmp-scope-b.lua")
    local path_c = vim.fs.joinpath(cwd, "tests", ".tmp-scope-c.lua")

    with_temp_files({
      [path_a] = { "return 'a'" },
      [path_b] = { "return 'b'" },
      [path_c] = { "return 'c'" },
    }, function()
      waystone.set(1, { path = path_a, row = 1, col = 0 }, scope_a)
      waystone.set(2, { path = path_b, row = 1, col = 0 }, scope_a)
      waystone.set(4, { path = path_c, row = 1, col = 0 }, scope_b)

      waystone.select(2, scope_a)

      local scope_b_cycle = waystone.cycle_next(scope_b)
      MiniTest.expect.equality(scope_b_cycle.slot, 4)

      local scope_a_cycle = waystone.cycle_next(scope_a)
      MiniTest.expect.equality(scope_a_cycle.slot, 1)
    end)
  end)
end

core_set["marks reload from the persisted data file"] = function()
  with_temp_data_file(function(data_file)
    local scope = vim.fn.getcwd()
    local path = vim.fs.joinpath(scope, "tests", ".tmp-persist.lua")

    with_temp_files({
      [path] = { "return 'persisted'" },
    }, function()
      waystone.set(3, { path = path, row = 1, col = 0 }, scope)

      core.reset_for_tests()
      waystone.setup({ data_file = data_file })

      MiniTest.expect.equality(waystone.list(scope), {
        {
          slot = 3,
          mark = { path = path, row = 1, col = 0 },
        },
      })
    end)
  end)
end

core_set["slot_for_file() and exists() locate marked files"] = function()
  with_temp_data_file(function()
    local scope = vim.fn.getcwd()
    local fixture = vim.fs.joinpath(scope, "tests", ".tmp-exists.lua")

    with_temp_files({
      [fixture] = { "return 'exists'" },
    }, function()
      waystone.set(2, { path = fixture, row = 5, col = 1 }, scope)

      MiniTest.expect.equality(waystone.slot_for_file(fixture, scope), 2)
      MiniTest.expect.equality(waystone.exists(fixture, scope), true)

      edit_at(fixture, 1, 0)
      MiniTest.expect.equality(waystone.slot_for_file(nil, scope), 2)
      MiniTest.expect.equality(waystone.exists(nil, scope), true)
    end)
  end)
end

core_set["current_slot() tracks active slot and clear_all() resets the scope"] = function()
  with_temp_data_file(function()
    local scope = vim.fn.getcwd()
    local path_a = vim.fs.joinpath(scope, "tests", ".tmp-current-slot-a.lua")
    local path_b = vim.fs.joinpath(scope, "tests", ".tmp-current-slot-b.lua")

    with_temp_files({
      [path_a] = { "return 'a'" },
      [path_b] = { "return 'b'" },
    }, function()
      waystone.set(1, { path = path_a, row = 1, col = 0 }, scope)
      waystone.set(3, { path = path_b, row = 4, col = 2 }, scope)

      MiniTest.expect.equality(waystone.current_slot(scope), 3)

      local cleared, err = waystone.clear_all(scope)
      MiniTest.expect.no_error(function()
        assert(cleared == 2 and not err)
      end)

      MiniTest.expect.equality(waystone.list(scope), {})
      MiniTest.expect.equality(waystone.current_slot(scope), nil)
    end)
  end)
end

core_set["quickfix() exports marks in slot order"] = function()
  with_temp_data_file(function()
    local scope = vim.fn.getcwd()
    local path_a = vim.fs.joinpath(scope, "tests", ".tmp-quickfix-a.lua")
    local path_b = vim.fs.joinpath(scope, "tests", ".tmp-quickfix-b.lua")

    with_temp_files({
      [path_a] = { "return 'a'" },
      [path_b] = { "return 'b'" },
    }, function()
      vim.fn.setqflist({}, "r")

      waystone.set(2, { path = path_b, row = 8, col = 4 }, scope)
      waystone.set(1, { path = path_a, row = 3, col = 1 }, scope)

      local count, err = waystone.quickfix(scope)
      MiniTest.expect.no_error(function()
        assert(count == 2 and not err)
      end)

      local qflist = vim.fn.getqflist()
      MiniTest.expect.equality(#qflist, 2)
      MiniTest.expect.equality(vim.api.nvim_buf_get_name(qflist[1].bufnr), path_a)
      MiniTest.expect.equality(qflist[1].lnum, 3)
      MiniTest.expect.equality(qflist[1].col, 2)
      MiniTest.expect.equality(qflist[1].text, string.format("[1] %s", vim.fn.fnamemodify(path_a, ":~:.")))
      MiniTest.expect.equality(vim.api.nvim_buf_get_name(qflist[2].bufnr), path_b)
      MiniTest.expect.equality(qflist[2].lnum, 8)
      MiniTest.expect.equality(qflist[2].col, 5)

      vim.cmd.cclose()
    end)
  end)
end

core_set["select_slot() supports opening marks in a split"] = function()
  with_temp_data_file(function()
    local scope = vim.fn.getcwd()
    local path = vim.fs.joinpath(scope, "tests", ".tmp-select-split.lua")

    with_temp_files({
      [path] = { "return 'split'", "return 'split-again'" },
    }, function()
      waystone.set(1, { path = path, row = 2, col = 0 }, scope)

      local before = #vim.api.nvim_tabpage_list_wins(0)
      local selected, err = core.select_slot(1, scope, vim.cmd.split)
      MiniTest.expect.no_error(function()
        assert(selected and not err)
      end)

      MiniTest.expect.equality(#vim.api.nvim_tabpage_list_wins(0), before + 1)
      MiniTest.expect.equality(vim.api.nvim_buf_get_name(0), path)
      MiniTest.expect.equality(vim.api.nvim_win_get_cursor(0), { 2, 0 })

      vim.cmd.only()
    end)
  end)
end

T["core"] = core_set

local command_set = MiniTest.new_set({
  hooks = {
    pre_case = function()
      waystone.setup()
      core.reset_for_tests()
      if vim.fn.exists(":WaystoneSet") == 0 then
        dofile(vim.fs.joinpath(vim.fn.getcwd(), "plugin", "waystone.lua"))
      end
    end,
  },
})

command_set["slot commands parse failures notify at ERROR"] = function()
  local expected = {
    WaystoneSet = "WaystoneSet: expected a slot number",
    WaystoneSelect = "WaystoneSelect: expected a slot number",
    WaystoneToggleSlot = "WaystoneToggleSlot: expected a slot number",
  }

  with_overrides(waystone, {
    set = function()
      error("WaystoneSet should not execute on parse failure")
    end,
    select = function()
      error("WaystoneSelect should not execute on parse failure")
    end,
    toggle = function()
      error("WaystoneToggleSlot should not execute on parse failure")
    end,
  }, function()
    for command_name, expected_message in pairs(expected) do
      with_notify_spy(function(notifications)
        vim.cmd(command_name .. " not-a-number")
        MiniTest.expect.equality(#notifications, 1)
        MiniTest.expect.equality(notifications[1].msg, expected_message)
        MiniTest.expect.equality(notifications[1].level, vim.log.levels.ERROR)
      end)
    end
  end)
end

command_set["slot command failures preserve notify-level asymmetry"] = function()
  local assertions = {
    {
      command = "WaystoneSet",
      expected_level = vim.log.levels.ERROR,
      expected_message = "waystone: set failed",
      replacement = function()
        return nil, "set failed"
      end,
      field = "set",
    },
    {
      command = "WaystoneSelect",
      expected_level = vim.log.levels.WARN,
      expected_message = "waystone: select failed",
      replacement = function()
        return nil, "select failed"
      end,
      field = "select",
    },
    {
      command = "WaystoneToggleSlot",
      expected_level = vim.log.levels.WARN,
      expected_message = "waystone: toggle failed",
      replacement = function()
        return nil, "toggle failed"
      end,
      field = "toggle",
    },
  }

  for _, spec in ipairs(assertions) do
    with_overrides(waystone, {
      [spec.field] = spec.replacement,
    }, function()
      with_notify_spy(function(notifications)
        vim.cmd(spec.command .. " 2")
        MiniTest.expect.equality(#notifications, 1)
        MiniTest.expect.equality(notifications[1].msg, spec.expected_message)
        MiniTest.expect.equality(notifications[1].level, spec.expected_level)
      end)
    end)
  end
end

command_set["WaystoneQuickfix notifies at WARN when the scope has no marks"] = function()
  with_notify_spy(function(notifications)
    vim.cmd("WaystoneQuickfix")
    MiniTest.expect.equality(#notifications, 1)
    MiniTest.expect.equality(notifications[1].msg, "waystone: no marks set for this scope")
    MiniTest.expect.equality(notifications[1].level, vim.log.levels.WARN)
  end)
end

command_set["WaystoneClearAll notifies cleared mark count"] = function()
  with_temp_data_file(function()
    local scope = vim.fn.getcwd()
    local fixture = vim.fs.joinpath(scope, "tests", ".tmp-clear-all.lua")

    with_temp_files({
      [fixture] = { "return 'clear-all'" },
    }, function()
      waystone.set(1, { path = fixture, row = 1, col = 0 }, scope)

      with_notify_spy(function(notifications)
        vim.cmd("WaystoneClearAll")
        MiniTest.expect.equality(#notifications, 1)
        MiniTest.expect.equality(notifications[1].msg, "waystone: cleared 1 mark(s)")
        MiniTest.expect.equality(notifications[1].level, vim.log.levels.INFO)
      end)

      MiniTest.expect.equality(waystone.list(scope), {})
    end)
  end)
end

T["commands"] = command_set

local scope_set = MiniTest.new_set({
  hooks = {
    pre_case = function()
      waystone.setup()
      core.reset_for_tests()
    end,
  },
})

scope_set["show_scope() warns when no git scope is detected"] = function()
  with_overrides(core, {
    detect_scope = function()
      return nil
    end,
  }, function()
    with_notify_spy(function(notifications)
      waystone.show_scope()
      MiniTest.expect.equality(#notifications, 1)
      MiniTest.expect.equality(notifications[1].msg, "waystone: no git-root scope detected")
      MiniTest.expect.equality(notifications[1].level, vim.log.levels.WARN)
    end)
  end)
end

scope_set["show_scope() reports mark count and configured slot capacity"] = function()
  with_temp_data_file(function(data_file)
    waystone.setup({ data_file = data_file, slots = 6 })
    core.reset_for_tests()

    local scope = vim.fn.getcwd()
    local fixture = vim.fs.joinpath(scope, "tests", ".tmp-scope-display.lua")

    with_temp_files({
      [fixture] = { "return 'scope'" },
    }, function()
      waystone.set(2, { path = fixture, row = 1, col = 0 }, scope)

      with_notify_spy(function(notifications)
        waystone.show_scope(scope)
        MiniTest.expect.equality(#notifications, 1)
        MiniTest.expect.equality(notifications[1].level, vim.log.levels.INFO)
        MiniTest.expect.equality(notifications[1].opts.title, "Waystone")
        MiniTest.expect.equality(notifications[1].msg:match("marks:%s+1 / 6"), "marks: 1 / 6")
      end)
    end)
  end)
end

T["scope"] = scope_set

return T
