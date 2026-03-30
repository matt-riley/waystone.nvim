local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local waystone = require("waystone")
local core = require("waystone.core")

local function with_temp_data_file(fn)
  local data_file = vim.fs.joinpath(vim.fn.getcwd(), "tests", ".tmp-waystone-data.json")
  vim.fn.delete(data_file)

  waystone.setup({ data_file = data_file })
  core.reset_for_tests()

  local ok, err = pcall(fn, data_file)

  vim.fn.delete(data_file)

  if not ok then
    error(err)
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
    error(err)
  end
end

local function edit_at(path, row, col)
  vim.cmd.edit(vim.fn.fnameescape(path))
  vim.api.nvim_win_set_cursor(0, { row, col })
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
  waystone.setup({ slots = 6 })
  MiniTest.expect.equality(waystone.config.slots, 6)
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

T["core"] = core_set

return T
