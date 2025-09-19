# nvim-tree-crossclip.nvim

Lightweight cross-session clipboard for `nvim-tree.lua` file operations.

This plugin persists `copy` and `cut` selections to disk so you can paste them
later, even across Neovim sessions. It integrates with `nvim-tree.lua` and
mirrors its clipboard while providing a shared, external clipboard file.

## Features

- **Copy/Cut toggles**: Mark files or folders to copy or cut.
- **Persistent clipboard**: Selections survive Neovim restarts.
- **Paste anywhere**: Paste into the directory under the cursor in `nvim-tree`.
- **Automatic cleanup**: Session-only selections are removed on exit.

## Requirements

- Neovim 0.9+ (uses `vim.system`, falls back if unavailable)
- [`nvim-tree.lua`](https://github.com/nvim-tree/nvim-tree.lua)

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "leonardcser/nvim-tree-crossclip.nvim",
  dependencies = "nvim-tree/nvim-tree.lua",
	name = "nvim-tree-crossclip",
  config = function()
    require("nvim-tree-crossclip").setup()
  end,
}
```

### Using [Packer](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "leonardcser/nvim-tree-crossclip.nvim",
  requires = "nvim-tree/nvim-tree.lua",
	name = "nvim-tree-crossclip",
  config = function()
    require("nvim-tree-crossclip").setup()
  end,
}
```

## Usage

This plugin exposes three Lua functions. Map them inside `nvim-tree`'s
`on_attach` so they only apply to the tree buffer. The default example below
uses single-key mappings `c`, `x`, and `p` to match a common workflow:

```lua
local function on_attach(bufnr)
  local api = require("nvim-tree.api")

  local function map(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = bufnr, noremap = true, silent = true, nowait = true, desc = desc })
  end

  local clip = require("nvim-tree-crossclip")
  map("c", clip.copy_toggle, "CrossClip: toggle copy")
  map("x", clip.cut_toggle,  "CrossClip: toggle cut")
  map("p", clip.paste,       "CrossClip: paste")
end

require("nvim-tree").setup({
  on_attach = on_attach,
})
```

## API

- `require("nvim-tree-crossclip").setup()`
- `require("nvim-tree-crossclip").copy_toggle()`
- `require("nvim-tree-crossclip").cut_toggle()`
- `require("nvim-tree-crossclip").paste()`

## How it works

- Clipboard file: `${stdpath("state")}/nvim_tree_clipboard.json`
- The file stores two arrays: `copy` and `cut`, and a timestamp.
- A filesystem watcher updates the in-memory session clipboard when the file
  changes.
- On `VimLeavePre`, session-only selections are subtracted and the file is
  rewritten.

## Notes

- Paste behavior uses shell commands: `mv` for cut, `cp -R -n` for copy (no
  overwrite). Errors are surfaced via `vim.notify`.
- After paste, the used list (`copy` or `cut`) is cleared to avoid duplicate
  pastes.
- The `nvim-tree` view is reloaded after paste.

## Help

After installation you can read `:h nvim-tree-crossclip` once helptags are
generated:

```vim
:helptags ALL
:h nvim-tree-crossclip
```
