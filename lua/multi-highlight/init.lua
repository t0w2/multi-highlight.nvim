-- multi-highlight.nvim
-- Highlight text patterns in rotating colors for visual code analysis.
-- Useful for tracing variables, comparing log fields, or marking patterns.

local M = {}

-- Defaults (overridable via setup())
local defaults = {
  bg_values = { '10', '30', '50', '70' },
  fg_values = { '80', 'A0', 'C0', 'E0' },
  separators = { '|', ',', ';', ':' },
  keys = {
    highlight_line     = '<C-H>',  -- normal: highlight quoted strings on line
    highlight_split    = '<C-H>',  -- visual: highlight selection, split by separators
    highlight_sel      = 'H',      -- visual: highlight selection as-is
    clear_all          = '<Leader>00',
  },
  -- Fixed-slot highlight groups.
  -- Visual \<slot><slot> adds, normal \<slot>0 removes.
  slots = {
    { group = 'Underlined' },
    { group = 'Error' },
    { group = 'IncSearch' },
    { group = 'TermCursor' },
    { group = 'TabLine' },
    { group = 'Substitute' },
    { group = 'Todo' },
  },
}

local config = vim.deepcopy(defaults)
local color_groups = {}
local ncgs = 0
local index = 0
local rotating_match_ids = {}
local fixed_match_ids = {}
local mapped_keys = {}

local function validate_color_values(values, name)
  if type(values) ~= 'table' or #values == 0 then
    error('multi-highlight: ' .. name .. ' must be a non-empty list', 2)
  end
  for _, value in ipairs(values) do
    if type(value) ~= 'string' or not value:match('^%x%x$') then
      error('multi-highlight: ' .. name .. ' values must be two-digit hex strings', 2)
    end
  end
end

--- Build the shuffled color palette.  Called once from setup().
local function build_palette()
  local bg = config.bg_values
  local fg = config.fg_values
  validate_color_values(bg, 'bg_values')
  validate_color_values(fg, 'fg_values')
  if #fg ~= #bg then
    error('multi-highlight: bg_values and fg_values must have the same length', 2)
  end

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
          reverse   = idx <= ncgs / 2,
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

local function literal_pattern(str, trim_text)
  if trim_text ~= false then str = trim(str) end
  if str == '' then return nil end
  return '\\V' .. str:gsub('\\', '\\\\'):gsub('\n', '\\n')
end

local function current_window_table(matches)
  local win = vim.api.nvim_get_current_win()
  matches[win] = matches[win] or {}
  return matches[win]
end

local function is_current_match(entry)
  for _, match in ipairs(vim.fn.getmatches()) do
    if match.id == entry.id and match.group == entry.group and match.pattern == entry.pattern then
      return true
    end
  end
  return false
end

local function clear_tracked_matches(matches)
  local ids = current_window_table(matches)
  for key, entry in pairs(ids) do
    if is_current_match(entry) then
      pcall(vim.fn.matchdelete, entry.id)
    end
    ids[key] = nil
  end
end

local function delete_tracked_match(matches, key)
  local ids = current_window_table(matches)
  local entry = ids[key]
  if entry then
    if is_current_match(entry) then
      pcall(vim.fn.matchdelete, entry.id)
    end
    ids[key] = nil
  end
end

--- Highlight a single text pattern with the next color in rotation.
---@param str string  pattern to highlight
---@param strip boolean  if true, strip surrounding quotes
---@param trim_text boolean|nil  if false, preserve leading/trailing whitespace
local function highlight_text(str, strip, trim_text)
  if strip then str = strip_quotes(str) end
  local pattern = literal_pattern(str, trim_text)
  if not pattern then return end
  local group = color_groups[index % ncgs + 1]
  local id = vim.fn.matchadd(group, pattern, 10)
  table.insert(current_window_table(rotating_match_ids), { id = id, group = group, pattern = pattern })
  index = index + 1
end

local function normalize_separator(separator)
  if separator == '\\|' then return '|' end
  return separator
end

--- Highlight text, optionally splitting by the first matching separator.
---@param str string
---@param strip boolean
---@param split boolean
---@param trim_text boolean|nil
local function highlight_patterns(str, strip, split, trim_text)
  if split then
    local separator
    local seps = config.separators or {}
    for i = 1, #seps do
      local candidate = normalize_separator(seps[i])
      if type(candidate) == 'string' and candidate ~= '' and str:find(candidate, 1, true) then
        separator = candidate
        break
      end
    end
    if separator then
      for _, pattern in ipairs(vim.split(str, separator, { plain = true })) do
        highlight_text(pattern, strip, trim_text)
      end
    else
      highlight_text(str, strip, trim_text)
    end
  else
    highlight_text(str, strip, trim_text)
  end
end

--- Highlight text.
---@param text string       text to highlight
---@param linewise boolean  if true, extract quoted substrings first
---@param split boolean     if true, split by separators
---@param strip boolean     if true, strip surrounding quotes
---@param trim_text boolean|nil  if false, preserve leading/trailing whitespace
local function highlight_text_patterns(text, linewise, split, strip, trim_text)
  if linewise then
    local found_quoted = false
    for _, str in text:gmatch("(['\"])(.-)%1") do
      found_quoted = true
      highlight_patterns(str, false, split, true)
    end
    if not found_quoted then
      highlight_patterns(text, false, split, true)
    end
  else
    highlight_patterns(text, strip, split, trim_text)
  end
end

--- Get the visual selection text without yanking.
---@return string
local function get_visual_selection()
  return table.concat(
    vim.fn.getregion(vim.fn.getpos('v'), vim.fn.getpos('.'), { type = vim.fn.mode() }), '\n')
end

local esc = vim.api.nvim_replace_termcodes('<Esc>', true, false, true)

local function clear_mapped_keys()
  for _, keymap in ipairs(mapped_keys) do
    pcall(vim.keymap.del, keymap.mode, keymap.lhs)
  end
  mapped_keys = {}
end

local function set_keymap(mode, lhs, rhs, opts)
  vim.keymap.set(mode, lhs, rhs, opts)
  table.insert(mapped_keys, { mode = mode, lhs = lhs })
end

--- Clear plugin match highlights (both rotating and fixed-slot).
function M.clear()
  clear_tracked_matches(rotating_match_ids)
  clear_tracked_matches(fixed_match_ids)
  index = 0
end

--- Set up keymaps and build the color palette.
---@param opts? table  override any field in the default config
function M.setup(opts)
  clear_mapped_keys()
  config = vim.deepcopy(defaults)
  if opts then
    for k, v in pairs(opts) do
      if k == 'keys' and type(v) == 'table' then
        config.keys = vim.tbl_extend('force', config.keys, v)
      else
        config[k] = v
      end
    end
  end

  build_palette()

  local keys = config.keys or {}

  -- Normal: read line, split quoted strings by separators, highlight each
  if keys.highlight_line then
    set_keymap('n', keys.highlight_line, function()
      local line = vim.api.nvim_get_current_line()
      highlight_text_patterns(line, true, true, false, true)
    end, { noremap = true, silent = true, desc = 'Highlight line patterns' })
  end

  -- Visual: split selection by separators, highlight each piece
  if keys.highlight_split then
    set_keymap('x', keys.highlight_split, function()
      local text = get_visual_selection()
      vim.api.nvim_feedkeys(esc, 'nx', false)
      highlight_text_patterns(text, false, true, true, true)
    end, { noremap = true, silent = true, desc = 'Highlight selection patterns' })
  end

  -- Visual: highlight selection as-is (no splitting)
  if keys.highlight_sel then
    set_keymap('x', keys.highlight_sel, function()
      local text = get_visual_selection()
      vim.api.nvim_feedkeys(esc, 'nx', false)
      highlight_text_patterns(text, false, false, false, false)
    end, { noremap = true, silent = true, desc = 'Highlight selection' })
  end

  -- Clear plugin highlights
  if keys.clear_all then
    set_keymap('n', keys.clear_all, M.clear, { silent = true, desc = 'Clear plugin highlights' })
  end

  -- Fixed-slot mappings: \NN to add, \N0 to remove
  for i, slot in ipairs(config.slots or {}) do
    local add_key = '<Leader>' .. i .. i
    local del_key = '<Leader>' .. i .. '0'
    set_keymap('x', add_key, function()
      local text = get_visual_selection()
      vim.api.nvim_feedkeys(esc, 'nx', false)
      local pattern = literal_pattern(text, false)
      if not pattern then return end
      delete_tracked_match(fixed_match_ids, i)
      local id
      if slot.id then
        local ok, result = pcall(vim.fn.matchadd, slot.group, pattern, 10, slot.id)
        id = ok and result or vim.fn.matchadd(slot.group, pattern, 10)
      else
        id = vim.fn.matchadd(slot.group, pattern, 10)
      end
      current_window_table(fixed_match_ids)[i] = { id = id, group = slot.group, pattern = pattern }
    end, { silent = true, desc = 'Highlight slot ' .. i .. ' (' .. slot.group .. ')' })
    set_keymap('n', del_key, function()
      delete_tracked_match(fixed_match_ids, i)
    end, { silent = true, desc = 'Remove highlight slot ' .. i })
  end
end

return M
