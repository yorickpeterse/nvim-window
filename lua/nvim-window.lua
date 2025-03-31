-- A simple and opinionated NeoVim plugin for switching between windows in the
-- current tab page.
local api = vim.api
local fn = vim.fn
local M = {}

-- The keycode for the Escape key, used to cancel the window picker.
-- local escape = 27
local escape = vim.fn.nr2char(27) -- yhb fix it

-- For the sake of keeping this plugin simple, we don't support changing the
-- dimensions of the floating window.
local float_height = 3
local float_width = 6

local config = {
  -- The characters available for hinting windows.
  chars = {
    'a',
    'b',
    'c',
    'd',
    'e',
    'f',
    'g',
    'h',
    'i',
    'j',
    'k',
    'l',
    'm',
    'n',
    'o',
    'p',
    'q',
    'r',
    's',
    't',
    'u',
    'v',
    'w',
    'x',
    'y',
    'z',
  },

  -- A group to use for overwriting the Normal highlight group in the floating
  -- window. This can be used to change the background color.
  normal_hl = 'Normal',

  -- The highlight group to apply to the line that contains the hint characters.
  -- This is used to make them stand out more.
  hint_hl = 'Bold',

  -- The border style to use for the floating window.
  border = 'single',

  -- How the hints should be rendered. The possible values are:
  --
  -- - "float" (default): renders the hints using floating windows
  -- - "status": renders the hints to a string and calls `redrawstatus`,
  --   allowing you to show the hints in a status or winbar line
  render = 'float',
}

local hints = {}

-- Returns a table that maps the hint keys to their corresponding windows.
local function window_keys(windows)
  local mapping = {}
  local chars = config.chars
  local nrs = {}
  local ids = {}
  local current = api.nvim_win_get_number(api.nvim_get_current_win())

  -- We use the window number (not the ID) as these are more consistent. This in
  -- turn should result in a more consistent choice of window keys.
  for _, win in ipairs(windows) do
    local nr = api.nvim_win_get_number(win)

    table.insert(nrs, nr)
    ids[nr] = win
  end

  table.sort(nrs)

  local index = 1

  for _, nr in ipairs(nrs) do
    -- We skip the current window here so that we still "reserve" it the
    -- character, but don't include it in the output. This ensures that window X
    -- always gets hint Y, regardless of what the current active window is.
    if nr ~= current then
      local key = chars[index]

      if mapping[key] then
        key = key .. (index == #chars and chars[1] or chars[index + 1])
      end

      mapping[key] = ids[nr]
    end

    index = index == #chars and 1 or index + 1
  end

  return mapping
end

-- Returns true if we need to ask for a second character.
local function ask_second_char(keys, start)
  for key, _ in pairs(keys) do
    if key ~= start and key:sub(1, 1) == start then
      return true
    end
  end

  return false
end

-- Opens all the floating windows in (roughly) the middle of every window.
local function open_floats(mapping)
  local floats = {}

  for key, window in pairs(mapping) do
    local bufnr = api.nvim_create_buf(false, true)

    if bufnr > 0 then
      local win_width = api.nvim_win_get_width(window)
      local win_height = api.nvim_win_get_height(window)

      local row = math.max(0, math.floor((win_height / 2) - 1))
      local col = math.max(0, math.floor((win_width / 2) - float_width))

      api.nvim_buf_set_lines(
        bufnr,
        0,
        -1,
        true,
        { '', '  ' .. key .. '  ', '' }
      )
      api.nvim_buf_add_highlight(bufnr, 0, config.hint_hl, 1, 0, -1)

      local float_window = api.nvim_open_win(bufnr, false, {
        relative = 'win',
        win = window,
        row = row,
        col = col,
        width = #key == 1 and float_width - 1 or float_width,
        height = float_height,
        focusable = false,
        style = 'minimal',
        border = config.border,
        noautocmd = true,
      })

      api.nvim_set_option_value(
        'winhl',
        'Normal:' .. config.normal_hl,
        { win = float_window }
      )
      api.nvim_set_option_value('diff', false, { win = float_window })

      floats[float_window] = bufnr
    end
  end

  -- We need to redraw here, otherwise the floats won't show up
  vim.cmd('redraw')

  return floats
end

local function close_floats(floats)
  for window, bufnr in pairs(floats) do
    api.nvim_win_close(window, true)
    api.nvim_buf_delete(bufnr, { force = true })
  end
end

local function get_char()
  local ok, char = pcall(fn.getchar)

  return ok and fn.nr2char(char) or nil
end

local function show_hints(keys, redraw)
  if config.render == 'status' then
    for key, win in pairs(keys) do
      hints[win] = key
    end

    if redraw then
      vim.cmd('redrawstatus!')
    end
  else
    return open_floats(keys)
  end
end

local function hide_hints(state, redraw)
  if config.render == 'status' then
    hints = {}

    if redraw then
      vim.cmd('redrawstatus!')
    end
  else
    close_floats(state)
  end
end

local function get_current_tabpage_winids()
  local to_remove = {}
  local windows = {}

  for _, id in pairs(api.nvim_tabpage_list_wins(0)) do
    local conf = api.nvim_win_get_config(id)

    if conf.relative == '' then
      table.insert(windows, id)
    end

    if conf.relative == 'win' and conf.focusable then
      table.insert(windows, id)
      to_remove[conf.win] = true
    end
  end

  for idx, win_id in pairs(windows) do
    if to_remove[win_id] then
      table.remove(windows, idx)
    end
  end
  return windows
end

-- note the hints_state for more than one characters choice
local function get_selected_winid(hints_state, win_keys)
  local key = get_char()
  if not key or key == escape then
    return nil
  end

  local window = win_keys[key]
  local extra = {}
  local choices = 0

  for hint, win in pairs(win_keys) do
    if vim.startswith(hint, key) then
      extra[hint] = win
      choices = choices + 1
    end
  end

  if choices > 1 then
    hide_hints(hints_state, true)
    hints_state = show_hints(extra, true)

    local second = get_char()

    if second then
      local combined = key .. second

      window = win_keys[combined] or win_keys[key]
    else
      window = nil
    end
  end

  return window
end

config.motions_map = {
  j = 'j',
  k = 'k',
  h = 'h',
  l = 'l',
  f = '',
  b = '',
  esc = '',
}

config.motions_leader = {
  {
    leader = ']',
    func = function(winid)
      local ch = get_char()
      if not ch or ch == config.motions_map.esc then
        return
      end
      vim.fn.win_execute(winid, 'normal ' .. ']' .. ch)
      vim.api.nvim__redraw({ win = winid, flush = true })
    end,
  },
  {
    leader = '[',
    func = function(winid)
      local ch = get_char()
      if not ch or ch == config.motions_map.esc then
        return
      end
      vim.fn.win_execute(winid, 'normal ' .. '[' .. ch)
      vim.api.nvim__redraw({ win = winid, flush = true })
    end,
  },
  {
    leader = 'z',
    func = function(winid)
      local ch = get_char()
      if not ch or ch == config.motions_map.esc then
        return
      end
      if ch == 'a' then
        vim.fn.win_execute(winid, 'foldo')
      elseif ch == 'o' then
        vim.fn.win_execute(winid, 'foldo!')
      elseif ch == 'O' then
        vim.fn.win_execute(winid, '%foldo!')
      else
        return
      end
      vim.api.nvim__redraw({ win = winid, flush = true })
    end,
  },
}

local function deal_with_motion(winid)
  while true do
    local ch = get_char()
    if not ch or ch == config.motions_map.esc then
      return
    end

    local is_normal = true

    -- leader function
    for _, pair in pairs(config.motions_leader) do
      if pair.leader == ch then
        is_normal = false
        pair.func(winid)
      end
    end

    -- normal function
    if is_normal then
      if config.motions_map[ch] then
        vim.fn.win_execute(winid, 'normal ' .. config.motions_map[ch])
      else
        vim.fn.win_execute(winid, 'normal ' .. ch)
      end
      vim.api.nvim__redraw({ win = winid, cursor = true, flush = true })
    end
  end
end

-- Returns the hint character(s) for the given window, or `nil` if there aren't
-- any.
--
-- This method only returns a value if the `render` option is set to `status`.
function M.hint(window)
  return hints[window]
end

-- Configures the plugin by merging the given settings into the default ones.
function M.setup(user_config)
  config = vim.tbl_extend('force', config, user_config)
end

-- select other window but just for move the text not for edit
function M.other()
  local wins = get_current_tabpage_winids()
  if #wins == 1 then
    return
  end
  if #wins == 2 then
    local x = wins[1] == vim.fn.bufwinid(0) and 1 or 2
    deal_with_motion(wins[x])
    return
  end

  local win_keys = window_keys(wins)
  local hints_state = show_hints(win_keys, true)
  local window = get_selected_winid(hints_state, win_keys)

  hide_hints(hints_state, true)
  if window then
    deal_with_motion(window)
  end
end

-- Picks a window to jump to, and makes it the active window.
function M.pick()
  local windows = get_current_tabpage_winids()

  local win_keys = window_keys(windows)
  local hints_state = show_hints(win_keys, true)
  local window = get_selected_winid(hints_state, win_keys)

  if window then
    api.nvim_set_current_win(window)
  end
  hide_hints(hints_state, true)
end

return M
