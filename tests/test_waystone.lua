local MiniTest = require("mini.test")
local T = MiniTest.new_set()

local waystone = require("waystone")

local setup_set = MiniTest.new_set({
  hooks = {
    pre_case = function()
      waystone.setup()
    end,
  },
})

setup_set["setup() initialises with empty config"] = function()
  MiniTest.expect.equality(type(waystone.config), "table")
end

setup_set["setup() merges user options"] = function()
  waystone.setup({ foo = "bar" })
  MiniTest.expect.equality(waystone.config.foo, "bar")
end

T["setup"] = setup_set

return T
