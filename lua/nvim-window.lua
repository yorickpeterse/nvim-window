-- A simple and opinionated NeoVim plugin for switching between windows in the
-- current tab page.
local api = vim.api
local fn = vim.fn
local M = {}

-- The keycode for the Escape key, used to cancel the window picker.
local escape = 27

-- For the sake of keeping this plugin simple, we don't support changing the
-- dimensions of the floating window.
local float_height = 3
local float_width = 6

local config = {
  -- The characters available for hinting windows.
  chars = {
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o',
    'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
  },

  -- A group to use for overwriting the Normal highlight group in the floating
  -- window. This can be used to change the background color.
  normal_hl = 'Normal',

  -- The highlight group to apply to the line that contains the hint characters.
  -- This is used to make them stand out more.
  hint_hl = 'Bold',

  -- The border style to use for the floating window.
  border = 'single'
}

local function is_regular_window(winid)
  return api.nvim_win_get_config(winid).relative == ''
end

-- Returns a table that maps the hint keys to their corresponding windows.
local function window_keys(windows)
  local mapping = {}
  local chars = config.chars

  for _, win in ipairs(windows) do
    -- We use the window number (not the ID) as these are more consistent. This
    -- in turn should result in a more consistent choice of window keys.
    local win_nr = api.nvim_win_get_number(win)
    local key = chars[(win_nr % #chars) + 1]

    if mapping[key] then
      key = key .. chars[((win_nr + 1) % #chars) + 1]
    end

    mapping[key] = win
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

      api.nvim_buf_set_lines(bufnr, 0, -1, true, { '', '  ' .. key .. '  ', '' })
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
        noautocmd = true
      })

      api.nvim_win_set_option(float_window, 'winhl', 'Normal:' .. config.normal_hl)
      api.nvim_win_set_option(float_window, 'diff', false)

      floats[float_window] = bufnr
    end
  end

  return floats
end

-- Configures the plugin by merging the given settings into the default ones.
function M.setup(user_config)
  config = vim.tbl_extend('force', config, user_config)
end

-- Picks a window to jump to, and makes it the active window.
function M.pick()
  local windows =
    vim.tbl_filter(is_regular_window, api.nvim_tabpage_list_wins(0))

  local window_keys = window_keys(windows)
  local floats = open_floats(window_keys)

  -- We need to redraw here, otherwise the floats won't show up until after the
  -- getchar() call.
  vim.cmd('redraw')

  local char = fn.getchar()
  local key = fn.nr2char(char)
  local window = window_keys[key]

  -- Only ask for the second character if we actually have a pair that starts
  -- with the first character.
  if not window and char ~= escape and ask_second_char(window_keys, key) then
    window = window_keys[key .. fn.nr2char(fn.getchar())]
  end

  for window, bufnr in pairs(floats) do
    api.nvim_win_close(window, true)
    api.nvim_buf_delete(bufnr, { force = true })
  end

  if window then
    api.nvim_set_current_win(window)
  end
end

return M
