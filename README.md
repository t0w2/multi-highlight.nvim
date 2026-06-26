# multi-highlight.nvim

Highlight text patterns in rotating colors for visual code analysis.

Useful for tracing variables across a file, comparing log fields side by
side, or marking multiple patterns while reading unfamiliar code.

## Features

- **Rotating color palette**: 64 auto-generated highlight groups with
  shuffled background/foreground combinations — each pattern gets a
  distinct color.
- **Separator-aware splitting**: `C-H` splits text by `|`, `,`, `;`, or
  `:` and highlights each piece in a different color. Useful for CSV
  lines, pipe-delimited log fields, or key:value pairs.
- **Fixed slots**: 7 named highlight slots (`\11`-`\77`) using built-in
  highlight groups (Underlined, Error, IncSearch, ...) with individual
  add/remove control.
- **Non-destructive**: reads visual selections directly via `getregion()`
  — never yanks or modifies the unnamed register.
- **Zero dependencies**: pure Neovim Lua, no external plugins required.
  Requires Neovim 0.10+.

## Installation

### lazy.nvim

```lua
{
  't0w2/multi-highlight.nvim',
  config = function() require('multi-highlight').setup() end,
}
```

## Usage

### Rotating highlights

| Key   | Mode   | Action |
|-------|--------|--------|
| `C-H` | normal | Extract quoted strings from current line, split by separators, highlight each piece |
| `C-H` | visual | Split selection by separators, highlight each piece |
| `H`   | visual | Highlight selection as-is (no splitting) |
| `\00` | normal | Clear all highlights |

### Fixed-slot highlights

Seven numbered slots using well-known highlight groups. Re-using a slot
replaces the previous pattern:

| Slot | Add (visual) | Remove (normal) | Highlight group |
|------|--------------|-----------------|-----------------|
| 1    | `\11`        | `\10`           | Underlined      |
| 2    | `\22`        | `\20`           | Error           |
| 3    | `\33`        | `\30`           | IncSearch       |
| 4    | `\44`        | `\40`           | TermCursor      |
| 5    | `\55`        | `\50`           | TabLine         |
| 6    | `\66`        | `\60`           | Substitute      |
| 7    | `\77`        | `\70`           | Todo            |

### Workflow example

1. Open a log file or code file
2. Press `C-H` on a line with `key1=val1|key2=val2|key3=val3` — each
   field gets a different color
3. Visually select a variable name, press `H` — all occurrences of the
   exact text are highlighted
4. Use `\11` to pin an important pattern to a stable color (Underlined)
5. `\00` to clear everything when done

## Configuration

All defaults can be overridden via `setup()`:

```lua
require('multi-highlight').setup({
  -- Background color components (combined as #RRGGBB from the grid)
  bg_values = { '10', '30', '50', '70' },
  -- Foreground color components
  fg_values = { '80', 'A0', 'C0', 'E0' },
  -- Separators tried in order; first match wins
  separators = { '\\|', ',', ';', ':' },
  -- Keymaps (set to false to disable individual mappings)
  keys = {
    highlight_line  = '<C-H>',      -- normal mode
    highlight_split = '<C-H>',      -- visual mode
    highlight_sel   = 'H',          -- visual mode, no split
    clear_all       = '<Leader>00',
  },
  -- Fixed-slot definitions (group = highlight group, id = matchadd ID)
  slots = {
    { group = 'Underlined', id = 901 },
    { group = 'Error',      id = 902 },
    -- ...up to 7 slots by default
  },
})
```

### Disabling specific keymaps

Set any key to `false` to skip that mapping (e.g., if `H` conflicts with
another plugin):

```lua
require('multi-highlight').setup({
  keys = { highlight_sel = false },
})
```

## API

```lua
local mh = require('multi-highlight')

mh.clear()    -- clear all match highlights (rotating + fixed slots)
```

## How the color palette works

The palette is built from a 4x4x4 grid of background and foreground color
values, producing 64 unique combinations. Each group alternates underline
on/off and uses reverse video for the first half of the palette, creating
visual variety. The groups are then randomly shuffled so consecutive
highlights are visually distinct.
