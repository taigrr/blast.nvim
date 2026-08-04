-- luacheck: ignore 122

local sent = {}
local timers = {}

package.preload['blast.socket'] = function()
  return {
    send_activity = function(payload)
      sent[#sent + 1] = payload
    end,
  }
end

package.preload['blast.utils'] = function()
  return {
    get_project_info = function()
      return 'demo-project', 'git@github.com:taigrr/demo.git', false, 'main'
    end,
    clear_project_cache = function() end,
    get_git_root = function()
      return '/tmp'
    end,
  }
end

package.preload['blast'] = function()
  return {
    is_stopped = function()
      return false
    end,
  }
end

local original_time = os.time
local original_uv = vim.uv
local original_api = {
  nvim_get_current_buf = vim.api.nvim_get_current_buf,
  nvim_buf_get_name = vim.api.nvim_buf_get_name,
  nvim_buf_line_count = vim.api.nvim_buf_line_count,
  nvim_buf_get_lines = vim.api.nvim_buf_get_lines,
  nvim_buf_is_valid = vim.api.nvim_buf_is_valid,
  nvim_create_augroup = vim.api.nvim_create_augroup,
  nvim_create_autocmd = vim.api.nvim_create_autocmd,
}
local original_bo = vim.bo
local original_schedule = vim.schedule
local original_schedule_wrap = vim.schedule_wrap
local original_defer_fn = vim.defer_fn
local original_notify = vim.notify

local now = 100
local current_buf = 1
local buffers = {
  [1] = {
    name = '/tmp/one.lua',
    lines = { 'hello world' },
    filetype = 'lua',
    buftype = '',
  },
}

local function new_timer()
  local timer = {
    closed = false,
    stopped = false,
  }

  function timer:start(_, _, callback)
    self.callback = callback
  end

  function timer:stop()
    self.stopped = true
  end

  function timer:close()
    self.closed = true
  end

  timers[#timers + 1] = timer
  return timer
end

os.time = function()
  return now
end

vim.uv = {
  new_timer = new_timer,
}

vim.api.nvim_get_current_buf = function()
  return current_buf
end

vim.api.nvim_buf_get_name = function(bufnr)
  return buffers[bufnr].name
end

vim.api.nvim_buf_line_count = function(bufnr)
  return #buffers[bufnr].lines
end

vim.api.nvim_buf_get_lines = function(bufnr)
  return buffers[bufnr].lines
end

vim.api.nvim_buf_is_valid = function(bufnr)
  return buffers[bufnr] ~= nil
end

vim.bo = setmetatable({}, {
  __index = function(_, bufnr)
    return {
      filetype = buffers[bufnr].filetype,
      buftype = buffers[bufnr].buftype,
    }
  end,
})

vim.schedule = function(callback)
  callback()
end

vim.schedule_wrap = function(callback)
  return callback
end

vim.api.nvim_create_augroup = function()
  return 1
end

vim.api.nvim_create_autocmd = function() end

vim.notify = function() end
vim.defer_fn = function(callback)
  callback()
end

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(string.format('%s\nexpected: %s\nactual: %s', message, vim.inspect(expected), vim.inspect(actual)))
  end
end

local ok, err = pcall(function()
  local tracker = require 'blast.tracker'

  tracker.setup {
    idle_timeout = 120,
    debounce_ms = 1000,
    debug = false,
  }

  tracker.on_buffer_activity()
  tracker.on_text_change()

  assert_eq(#timers, 3, 'setup, activity, and text change should create flush, idle, and debounce timers')

  now = now + 20
  tracker.end_session()

  for index, timer in ipairs(timers) do
    assert_eq(timer.closed, true, string.format('timer %d should be closed when the session ends', index))
  end
end)

os.time = original_time
vim.uv = original_uv
vim.api.nvim_get_current_buf = original_api.nvim_get_current_buf
vim.api.nvim_buf_get_name = original_api.nvim_buf_get_name
vim.api.nvim_buf_line_count = original_api.nvim_buf_line_count
vim.api.nvim_buf_get_lines = original_api.nvim_buf_get_lines
vim.api.nvim_buf_is_valid = original_api.nvim_buf_is_valid
vim.bo = original_bo
vim.schedule = original_schedule
vim.schedule_wrap = original_schedule_wrap
vim.defer_fn = original_defer_fn
vim.notify = original_notify
vim.api.nvim_create_augroup = original_api.nvim_create_augroup
vim.api.nvim_create_autocmd = original_api.nvim_create_autocmd

if not ok then
  error(err)
end
