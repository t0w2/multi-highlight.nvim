local source = debug.getinfo(1, 'S').source:sub(2)
local root = vim.fn.fnamemodify(source, ':p:h:h')
vim.opt.runtimepath:append(root)

local mh = require('multi-highlight')
local tests = {}

local function test(name, fn)
  table.insert(tests, { name = name, fn = fn })
end

local function fail(msg)
  error(msg, 2)
end

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    fail(string.format('%s: expected %s, got %s', msg or 'assertion failed', vim.inspect(expected), vim.inspect(actual)))
  end
end

local function assert_true(value, msg)
  if not value then fail(msg or 'expected truthy value') end
end

local function map_by_desc(mode, desc)
  for _, map in ipairs(vim.api.nvim_get_keymap(mode)) do
    if map.desc == desc then return map end
  end
  fail('missing mapping: ' .. mode .. ' ' .. desc)
end

local function assert_no_map_by_desc(mode, desc)
  for _, map in ipairs(vim.api.nvim_get_keymap(mode)) do
    if map.desc == desc then fail('unexpected mapping: ' .. mode .. ' ' .. desc) end
  end
end

local function setup(opts)
  mh.setup(opts)
end

local function before_each(opts)
  pcall(vim.cmd, 'silent! only!')
  vim.fn.clearmatches()
  setup(opts)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { '' })
end

local function run_line_highlight(line, opts)
  before_each(opts)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
  map_by_desc('n', 'Highlight line patterns').callback()
  return vim.fn.getmatches()
end

local function run_visual_map(desc, line, start_col, end_col, opts)
  before_each(opts)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
  vim.api.nvim_win_set_cursor(0, { 1, start_col - 1 })
  vim.cmd('normal! v')
  vim.api.nvim_win_set_cursor(0, { 1, end_col - 1 })
  map_by_desc('x', desc).callback()
  return vim.fn.getmatches()
end

test('setup merges partial key config and removes disabled mappings on repeat setup', function()
  before_each({ keys = { highlight_sel = false } })
  map_by_desc('n', 'Highlight line patterns')
  map_by_desc('n', 'Clear plugin highlights')
  assert_no_map_by_desc('x', 'Highlight selection')

  setup()
  map_by_desc('x', 'Highlight selection')

  setup({ keys = { highlight_sel = false } })
  assert_no_map_by_desc('x', 'Highlight selection')
end)

test('default pipe separator splits into literal matches', function()
  local matches = run_line_highlight('a|b|c')
  assert_eq(#matches, 3, 'match count')
  assert_eq(matches[1].pattern, '\\Va', 'first pattern')
  assert_eq(matches[2].pattern, '\\Vb', 'second pattern')
  assert_eq(matches[3].pattern, '\\Vc', 'third pattern')
end)

test('legacy escaped pipe separator remains compatible', function()
  local matches = run_line_highlight('a|b|c', { separators = { '\\|' } })
  assert_eq(#matches, 3, 'match count')
  assert_eq(matches[1].pattern, '\\Va', 'first pattern')
  assert_eq(matches[2].pattern, '\\Vb', 'second pattern')
  assert_eq(matches[3].pattern, '\\Vc', 'third pattern')
end)

test('separator order uses the first configured separator that appears', function()
  local matches = run_line_highlight('a,b|c')
  assert_eq(#matches, 2, 'match count')
  assert_eq(matches[1].pattern, '\\Va,b', 'first pattern')
  assert_eq(matches[2].pattern, '\\Vc', 'second pattern')
end)

test('empty split fields are skipped', function()
  local matches = run_line_highlight('|a,,b|')
  assert_eq(#matches, 1, 'match count')
  assert_eq(matches[1].pattern, '\\Va,,b', 'first pattern')

  matches = run_line_highlight('a,,b')
  assert_eq(#matches, 2, 'comma match count')
  assert_eq(matches[1].pattern, '\\Va', 'first comma pattern')
  assert_eq(matches[2].pattern, '\\Vb', 'second comma pattern')
end)

test('regex metacharacters are highlighted literally', function()
  local matches = run_line_highlight('foo.bar,a[0],$var')
  assert_eq(#matches, 3, 'match count')
  assert_eq(matches[1].pattern, '\\Vfoo.bar', 'dot pattern')
  assert_eq(matches[2].pattern, '\\Va[0]', 'bracket pattern')
  assert_eq(matches[3].pattern, '\\V$var', 'dollar pattern')
end)

test('quoted substrings are extracted and split independently', function()
  local matches = run_line_highlight([[msg='alpha|beta' other="gamma,delta"]])
  assert_eq(#matches, 4, 'match count')
  assert_eq(matches[1].pattern, '\\Valpha', 'first quoted pattern')
  assert_eq(matches[2].pattern, '\\Vbeta', 'second quoted pattern')
  assert_eq(matches[3].pattern, '\\Vgamma', 'third quoted pattern')
  assert_eq(matches[4].pattern, '\\Vdelta', 'fourth quoted pattern')
end)

test('unmatched apostrophes fall back to whole-line highlighting', function()
  local matches = run_line_highlight([[don't panic]])
  assert_eq(#matches, 1, 'match count')
  assert_eq(matches[1].pattern, [[\Vdon't panic]], 'fallback pattern')
end)

test('visual H preserves exact selected quotes and whitespace', function()
  local matches = run_visual_map('Highlight selection', ' "foo" foo', 1, 6)
  assert_eq(#matches, 1, 'match count')
  assert_eq(matches[1].pattern, '\\V "foo"', 'visual exact pattern')
end)

test('visual split trims and strips split pieces', function()
  local matches = run_visual_map('Highlight selection patterns', ' "a,b" ', 1, 7)
  assert_eq(#matches, 2, 'match count')
  assert_eq(matches[1].pattern, '\\Va', 'first split pattern')
  assert_eq(matches[2].pattern, '\\Vb', 'second split pattern')
end)

test('clear preserves unrelated matches in the current window', function()
  before_each()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'a,b', 'external' })
  vim.fn.matchadd('Search', 'external')
  map_by_desc('n', 'Highlight line patterns').callback()
  assert_eq(#vim.fn.getmatches(), 3, 'pre-clear match count')

  mh.clear()
  local matches = vim.fn.getmatches()
  assert_eq(#matches, 1, 'post-clear match count')
  assert_eq(matches[1].pattern, 'external', 'external pattern')
end)

test('clear is scoped to the current window', function()
  before_each()
  local first_win = vim.api.nvim_get_current_win()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'a,b' })
  map_by_desc('n', 'Highlight line patterns').callback()
  assert_eq(#vim.fn.getmatches(), 2, 'first window pre-clear count')

  vim.cmd('vsplit')
  local second_win = vim.api.nvim_get_current_win()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'c,d' })
  map_by_desc('n', 'Highlight line patterns').callback()
  assert_eq(#vim.fn.getmatches(), 2, 'second window pre-clear count')

  mh.clear()
  assert_eq(#vim.fn.getmatches(), 0, 'second window post-clear count')

  vim.api.nvim_set_current_win(first_win)
  assert_eq(#vim.fn.getmatches(), 2, 'first window remains highlighted')
  mh.clear()
  assert_eq(#vim.fn.getmatches(), 0, 'first window cleanup count')

  vim.api.nvim_set_current_win(second_win)
  vim.cmd('close!')
end)

test('fixed slot add replaces its own previous match', function()
  local matches = run_visual_map('Highlight slot 1 (Underlined)', 'first second', 1, 5)
  assert_eq(#matches, 1, 'first slot count')
  assert_eq(matches[1].pattern, '\\Vfirst', 'first slot pattern')

  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'first second' })
  vim.api.nvim_win_set_cursor(0, { 1, 6 })
  vim.cmd('normal! v5l')
  map_by_desc('x', 'Highlight slot 1 (Underlined)').callback()
  matches = vim.fn.getmatches()
  assert_eq(#matches, 1, 'replacement slot count')
  assert_eq(matches[1].pattern, '\\Vsecond', 'replacement slot pattern')
end)

test('fixed slot remove does not delete unrelated matches using old fixed IDs', function()
  before_each()
  vim.fn.matchadd('Search', 'external', 10, 901)
  map_by_desc('n', 'Remove highlight slot 1').callback()
  local matches = vim.fn.getmatches()
  assert_eq(#matches, 1, 'external match count')
  assert_eq(matches[1].id, 901, 'external id')
end)

test('fixed slot falls back when an optional configured ID collides', function()
  local matches = run_visual_map('Highlight slot 1 (Underlined)', 'slot text', 1, 4, {
    slots = { { group = 'Underlined', id = 901 } },
  })
  assert_eq(#matches, 1, 'slot-only count')

  before_each({ slots = { { group = 'Underlined', id = 901 } } })
  vim.fn.matchadd('Search', 'external', 10, 901)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'slot text' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd('normal! v3l')
  map_by_desc('x', 'Highlight slot 1 (Underlined)').callback()
  matches = vim.fn.getmatches()
  assert_eq(#matches, 2, 'collision fallback count')
  assert_true(matches[1].id == 901 or matches[2].id == 901, 'external id should remain present')
end)

test('palette configuration is validated', function()
  before_each()
  local ok, err = pcall(function()
    mh.setup({ fg_values = { '80' } })
  end)
  assert_true(not ok and tostring(err):find('same length', 1, true), 'mismatched color lengths should fail')

  ok, err = pcall(function()
    mh.setup({ bg_values = {} })
  end)
  assert_true(not ok and tostring(err):find('non-empty list', 1, true), 'empty color list should fail')

  ok, err = pcall(function()
    mh.setup({ bg_values = { 'GG' }, fg_values = { '80' } })
  end)
  assert_true(not ok and tostring(err):find('two-digit hex', 1, true), 'invalid hex should fail')
end)

test('setup resets custom separators back to defaults', function()
  local matches = run_line_highlight('a|b', { separators = { ',' } })
  assert_eq(#matches, 1, 'custom comma-only separator count')
  assert_eq(matches[1].pattern, '\\Va|b', 'custom comma-only pattern')

  matches = run_line_highlight('a|b')
  assert_eq(#matches, 2, 'default separator restored count')
end)

local failures = 0
for _, case in ipairs(tests) do
  local ok, err = xpcall(case.fn, debug.traceback)
  if ok then
    print('ok - ' .. case.name)
  else
    failures = failures + 1
    print('not ok - ' .. case.name)
    print(err)
  end
end

if failures > 0 then
  print(string.format('%d/%d tests failed', failures, #tests))
  vim.cmd('cquit 1')
end

print(string.format('%d tests passed', #tests))
vim.cmd('qa!')
