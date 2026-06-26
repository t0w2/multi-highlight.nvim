-- multi-highlight.nvim
-- Highlight text patterns in rotating colors for visual code analysis.
-- Useful for tracing variables, comparing log fields, or marking patterns.

local M = {}

-- Defaults (overridable via setup())
local config = {
  bg_values = { '10', '30', '50', '70' },
  fg_values = { '80', 'A0', 'C0', 'E0' },
  separators = { '\\|', ',', ';', ':' },
  keys = {
    highlight_line     = '<C-H>',  -- normal: highlight quoted strings on line
    highlight_split    = '<C-H>',  -- visual: highlight selection, split by separators
    highlight_sel      = 'H',      -- visual: highlight selection as-is
    clear_all          = '<Leader>00',
  },
  -- Fixed-slot highlight groups and their match IDs.
  -- Visual \<slot><slot> adds, normal \<slot>0 removes.
  slots = {
    { group = 'Underlined',  id = 901 },
    { group = 'Error',       id = 902 },
    { group = 'IncSearch',   id = 903 },
    { group = 'TermCursor',  id = 904 },
    { group = 'TabLine',     id = 905 },
    { group = 'Substitute',  id = 906 },
    { group = 'Todo',        id = 907 },
  },
}

local color_groups = {}
local ncgs = 0
local index = 0

--- Build the shuffled color palette.  Called once from setup().
local function build_palette()
  local bg = config.bg_values
  local fg = config.fg_values
  local nc = #bg
  ncgs = nc ^ 3

  color_groups = {}
  math.randomseed(os.time())

  local idx = 0
  for i = 1, nc do
    for j = 1, nc do
      for k = 1, nc do
        local bgcolor = '#' .. bg[i] .. bg[j] .. bg[k]
        local fgcolor = '#' .. fg[i] .. fg[j] .. fg[k]
        idx = idx + 1
        local name = 'MHCG' .. idx
        vim.api.nvim_set_hl(0, name, {
          underline = idx % 2 == 1,
          reverse   = idx < ncgs / 2,
          fg = fgcolor,
          bg = bgcolor,
        })
        table.insert(color_groups, math.random(#color_groups + 1), name)
      end
    end
  end
  index = 0
end

--- Trim leading/trailing whitespace and trailing CR/LF.
---@param str string
---@return string
local function trim(str)
  return str:gsub('^[%s]*(.-)[%s\r\n]*$', '%1')
end

--- Strip surrounding quotation marks and whitespace.
---@param str string
---@return string
local function strip_quotes(str)
  return str:gsub("^%s*['\"]*(.-)['\"]*%s*$", '%1')
end

--- Highlight a single text pattern with the next color in rotation.
---@param str string  pattern to highlight
---@param stripped boolean  if true, skip quote stripping
local function highlight_text(str, stripped)
  if not stripped then str = strip_quotes(str) end
  vim.fn.matchadd(color_groups[index % ncgs + 1], trim(str), 10)
  index = index + 1
end

--- Highlight text, optionally splitting by the first matching separator.
---@param str string
---@param stripped boolean
---@param split boolean
local function highlight_patterns(str, stripped, split)
  if split then
    local seps = config.separators
    local patterns
    for i = 1, #seps do
      if str:find(seps[i]) then
        patterns = vim.gsplit(str, seps[i])
        break
      end
    end
    if patterns == nil then
      patterns = vim.gsplit(str, seps[1])
    end
    for pattern in patterns do
      highlight_text(pattern, stripped)
    end
  else
    highlight_text(str, stripped)
  end
end

--- Highlight text.
---@param text string       text to highlight
---@param linewise boolean  if true, extract quoted substrings first
---@param split boolean     if true, split by separators
local function highlight_text_patterns(text, linewise, split)
  if linewise then
    if text:find("[\"']") then
      for str in text:gmatch("['\"][^'\"]+['\"]") do
        highlight_patterns(strip_quotes(str), true, split)
      end
    else
      highlight_patterns(text, true, split)
    end
  else
    highlight_patterns(text, false, split)
  end
end

--- Get the visual selection text without yanking.
---@return string
local function get_visual_selection()
  return table.concat(
    vim.fn.getregion(vim.fn.getpos('v'), vim.fn.getpos('.'), { type = vim.fn.mode() }), '\n')
end

local esc = vim.api.nvim_replace_termcodes('<Esc>', true, false, true)

--- Clear all match highlights (both rotating and fixed-slot).
function M.clear()
  vim.fn.clearmatches()
end

--- Set up keymaps and build the color palette.
---@param opts? table  override any field in the default config
function M.setup(opts)
  if opts then
    -- Merge top-level keys; nested tables are replaced wholesale
    for k, v in pairs(opts) do config[k] = v end
  end

  build_palette()

  local keys = config.keys

  -- Normal: yank line, split quoted strings by separators, highlight each
  if keys.highlight_line then
    vim.keymap.set('n', keys.highlight_line, function()
      local line = vim.api.nvim_get_current_line()
      highlight_text_patterns(line, true, true)
    end, { noremap = true, silent = true, desc = 'Highlight line patterns' })
  end

  -- Visual: split selection by separators, highlight each piece
  if keys.highlight_split then
    vim.keymap.set('x', keys.highlight_split, function()
      local text = get_visual_selection()
      vim.api.nvim_feedkeys(esc, 'nx', false)
      highlight_text_patterns(text, false, true)
    end, { noremap = true, silent = true, desc = 'Highlight selection patterns' })
  end

  -- Visual: highlight selection as-is (no splitting)
  if keys.highlight_sel then
    vim.keymap.set('x', keys.highlight_sel, function()
      local text = get_visual_selection()
      vim.api.nvim_feedkeys(esc, 'nx', false)
      highlight_text_patterns(text, false, false)
    end, { noremap = true, silent = true, desc = 'Highlight selection' })
  end

  -- Clear all highlights
  if keys.clear_all then
    vim.keymap.set('n', keys.clear_all, M.clear, { silent = true, desc = 'Clear all highlights' })
  end

  -- Fixed-slot mappings: \NN to add, \N0 to remove
  for i, slot in ipairs(config.slots) do
    local add_key = '<Leader>' .. i .. i
    local del_key = '<Leader>' .. i .. '0'
    vim.keymap.set('x', add_key, function()
      local text = get_visual_selection()
      vim.api.nvim_feedkeys(esc, 'nx', false)
      pcall(vim.fn.matchdelete, slot.id)
      vim.fn.matchadd(slot.group, vim.fn.escape(text, '\\/.*$^~[]'), 10, slot.id)
    end, { silent = true, desc = 'Highlight slot ' .. i .. ' (' .. slot.group .. ')' })
    vim.keymap.set('n', del_key, function()
      pcall(vim.fn.matchdelete, slot.id)
    end, { silent = true, desc = 'Remove highlight slot ' .. i })
  end
end

return M
