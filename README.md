# waystone.nvim

> Navigate your Neovim project like a fantasy hero — drop waystones to mark
> locations and jump between them instantly.

<!-- Uncomment badges after pushing to GitHub:
[![CI](https://github.com/mattriley/waystone.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/mattriley/waystone.nvim/actions/workflows/ci.yml)
-->

## Features

- Store persistent slot-based marks at buffer positions
- Scope marks by git root by default, or by `cwd`, `global`, `git_branch`, or an explicit scope override
- Jump directly to a slot or cycle through populated slots
- Export the current scope to quickfix or clear it in one step
- Inspect marks through a lightweight floating list and scope summary
- Keep the current v1 surface usable from both commands and a small Lua API

## Requirements

- Neovim 0.8+

## Versioning

- Canonical project version is stored in [`VERSION`](VERSION).
- `release-please` updates both `VERSION` and `CHANGELOG.md`.

## Installation

```lua
-- lazy.nvim
{ "mattriley/waystone.nvim", opts = {} }

-- packer.nvim
use { "mattriley/waystone.nvim", config = function() require("waystone").setup() end }
```

## Usage

The current plugin surface includes a small Lua API and a handful of built-in
commands.

```lua
local waystone = require("waystone")

waystone.setup({
  slots = 4,
  scope_mode = "git",
})

vim.keymap.set("n", "<leader>m1", function()
  waystone.toggle(1)
end)

vim.keymap.set("n", "<leader>m2", function()
  waystone.select(2)
end)

vim.keymap.set("n", "]m", waystone.cycle_next)
vim.keymap.set("n", "[m", waystone.cycle_prev)
vim.keymap.set("n", "<leader>ml", waystone.open_list)
```

All API calls use the configured `scope_mode` when `scope` is omitted. The
default remains the current buffer's git root, and you can still pass an
explicit `scope` string any time you want to override that resolution.

### Commands

- `:WaystoneList` opens the floating marks list.
- `:WaystoneToggle` toggles that list window.
- `:WaystoneScope` shows the active scope path and mark count.
- `:WaystoneQuickfix` exports the current scope to quickfix and opens it.
- `:WaystoneClearAll` clears all populated slots in the current scope.
- `:WaystoneSet {slot}` saves the current cursor location into a slot.
- `:WaystoneSelect {slot}` jumps to a saved slot.
- `:WaystoneToggleSlot {slot}` toggles a slot at the current cursor location.
- `:WaystoneNext` and `:WaystonePrev` cycle through populated slots.

## Configuration

```lua
require("waystone").setup({})
```

### Options

- `slots` (default: `4`): number of slot-oriented marks stored per scope.
- `data_file`: optional path override for the JSON file used to persist marks.
- `scope_mode` (default: `"git"`): built-in default scope resolver. Supported
  values are `"git"`, `"cwd"`, `"global"`, and `"git_branch"`.

## API

- `detect_scope()` -> detect the resolved default scope for the current buffer.
- `list(scope?)` -> list populated slots for a scope.
- `slot_for_file(path?, scope?)` -> return the slot currently holding a file.
- `exists(path?, scope?)` -> check whether a file is already marked.
- `current_slot(scope?)` -> return the slot currently tracked for cycling.
- `set(slot, mark?, scope?)` -> save an explicit mark or the current cursor
  location.
- `clear(slot, scope?)` -> clear a slot.
- `toggle(slot, scope?)` -> set/clear a slot using the current cursor location.
- `select(slot, scope?)` -> jump to a saved mark.
- `cycle_next(scope?)` / `cycle_prev(scope?)` -> move through populated slots.
- `quickfix(scope?)` -> export the current scope to quickfix in slot order.
- `clear_all(scope?)` -> clear all populated slots in a scope.
- `open_list(scope?)` / `toggle_list(scope?)` -> show or toggle the floating
  marks list.
- `show_scope(scope?)` -> display the active scope and mark count.
- `toggle_file(scope?)` -> toggle the current file into the lowest free slot, or
  clear its existing slot.
- `data_path()` -> inspect the resolved persistence file path.

## List window

The floating list stays read-only, but it now supports a few extra actions:

- `<CR>` opens the slot under the cursor.
- `d` clears the slot under the cursor.
- `1`-`9` jump directly to visible slots.
- `<C-s>` opens the selected slot in a horizontal split.
- `|` opens the selected slot in a vertical split.
- `<C-q>` exports the current scope to quickfix.
- `q` or `<Esc>` close the window.

See `:help waystone` for the generated reference docs.

## Development

### Testing

Tests use [mini.test](https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-test.md). Run them with:

```bash
MINI_PATH=/path/to/mini.nvim make test
```

If `mini.nvim` is already on your Neovim runtimepath, plain `make test` also
works. Or run the underlying headless command manually:

```bash
MINI_PATH=/path/to/mini.nvim \
  nvim --headless -u tests/minimal_init.lua \
  -c "lua MiniTest.run({})" -c "qa"
```

### Linting

```bash
make lint
```

### Formatting

```bash
make format        # auto-format
make format-check  # check only (CI uses this)
```

### Documentation (`:help`)

Plugin help is generated from Lua annotations in `lua/waystone/init.lua` using
[mini.doc](https://github.com/nvim-mini/mini.doc):

```bash
MINI_PATH=/path/to/mini.nvim make docs
```

`make docs` injects the current value from [`VERSION`](VERSION) into the
generated vim help file.

## License

[MIT](LICENSE)
