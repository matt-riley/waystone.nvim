# waystone.nvim

> Navigate your Neovim project like a fantasy hero — drop waystones to mark
> locations and jump between them instantly.

<!-- Uncomment badges after pushing to GitHub:
[![Tests](https://github.com/mattriley/waystone.nvim/actions/workflows/tests.yml/badge.svg)](https://github.com/mattriley/waystone.nvim/actions/workflows/tests.yml)
[![Lint](https://github.com/mattriley/waystone.nvim/actions/workflows/lint.yml/badge.svg)](https://github.com/mattriley/waystone.nvim/actions/workflows/lint.yml)
[![Format](https://github.com/mattriley/waystone.nvim/actions/workflows/format.yml/badge.svg)](https://github.com/mattriley/waystone.nvim/actions/workflows/format.yml)
-->

## Features

- Drop persistent waystones at any buffer position
- Jump between waystones with a single keymap
- Per-project waystone sets scoped to the working directory
- Telescope picker for fuzzy-finding across all waystones (planned)

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

```vim
:Waystone
```

## Configuration

```lua
require("waystone").setup({})
```

### Options

> Configuration options will be documented here as the plugin is developed.

## Development

### Testing

Tests use [mini.test](https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-test.md). Run them with:

```bash
make test
```

Or manually:

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
make docs
```

`make docs` injects the current value from [`VERSION`](VERSION) into the
generated vim help file.

## License

[MIT](LICENSE)
