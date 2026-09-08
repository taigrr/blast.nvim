local callbacks = {}
local pipes = {}
local timers = {}

package.loaded['blast.socket'] = nil

package.preload['blast.utils'] = function()
  return {
    find_blastd_bin = function()
      return nil
    end,
  }
end

local original_uv = vim.uv
local original_loop = vim.loop
local original_schedule = vim.schedule
local original_schedule_wrap = vim.schedule_wrap
local original_defer_fn = vim.defer_fn

local function new_pipe()
  local pipe = {
    closed = false,
    stopped = false,
  }

  function pipe.connect(_, _path, callback)
    callback(nil)
  end

  function pipe.read_start(_, callback)
    pipe.read_callback = callback
  end

  function pipe:read_stop()
    self.stopped = true
  end

  function pipe.write(_, _json, callback)
    callbacks[#callbacks + 1] = callback
  end

  function pipe:close()
    self.closed = true
  end

  pipes[#pipes + 1] = pipe
  return pipe
end

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

vim.uv = {
  fs_stat = function()
    return nil
  end,
  new_pipe = new_pipe,
  new_timer = new_timer,
}
vim.loop = vim.uv
vim.schedule = function(callback)
  callback()
end
vim.schedule_wrap = function(callback)
  return callback
end
vim.defer_fn = function() end

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(string.format('%s\nexpected: %s\nactual: %s', message, vim.inspect(expected), vim.inspect(actual)))
  end
end

local ok, err = pcall(function()
  local socket = require 'blast.socket'

  socket.setup {
    socket_path = '/tmp/blastd.sock',
    request_timeout_ms = 25,
    debug = false,
  }

  local result_ok = nil
  local result = nil
  socket.send_sync(function(callback_ok, callback_result)
    result_ok = callback_ok
    result = callback_result
  end)

  assert_eq(#pipes, 1, 'sync request should open a dedicated pipe')
  assert_eq(#timers, 1, 'sync request should start one timeout timer')

  timers[1].callback()

  assert_eq(result_ok, false, 'timeout should report failure')
  assert_eq(result, 'request timed out', 'timeout should report a useful error')
  assert_eq(pipes[1].stopped, true, 'timeout should stop reading from the request pipe')
  assert_eq(pipes[1].closed, true, 'timeout should close the request pipe')
  assert_eq(timers[1].closed, true, 'timeout should close its timer')

  callbacks[1](nil)
  assert_eq(result, 'request timed out', 'late write callbacks should not change the completed result')
end)

vim.uv = original_uv
vim.loop = original_loop
vim.schedule = original_schedule
vim.schedule_wrap = original_schedule_wrap
vim.defer_fn = original_defer_fn

if not ok then
  error(err)
end
