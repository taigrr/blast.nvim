local M = {}

M.config = {
  socket_path = vim.fn.expand '~/.local/share/blastd/blastd.sock',
  idle_timeout = 120,
  debounce_ms = 1000,
  debug = false,
}

local initialized = false

function M.setup(opts)
  if initialized then
    return
  end
  initialized = true

  M.config = vim.tbl_deep_extend('force', M.config, opts or {})

  local socket = require 'blast.socket'
  local tracker = require 'blast.tracker'

  socket.setup(M.config)
  tracker.setup(M.config)
  socket.start_keepalive()

  if M.config.debug then
    vim.notify('[blast.nvim] initialized', vim.log.levels.INFO)
  end
end

function M.status()
  local socket = require 'blast.socket'
  local tracker = require 'blast.tracker'

  local connected = socket.is_connected()
  local session = tracker.get_session()

  local lines = {
    'blast.nvim status:',
    string.format('  Socket: %s', connected and 'connected' or 'disconnected'),
    string.format('  Socket path: %s', M.config.socket_path),
  }

  if session then
    local filetype = nil
    local file_count = 0
    local current = tracker.get_current_file()
    if current then
      filetype = current.filetype
    end
    file_count = tracker.get_file_count()
    lines[#lines + 1] = string.format('  Current session: %s', session.project or 'unknown')
    lines[#lines + 1] = string.format('  Filetype: %s', filetype or 'unknown')
    lines[#lines + 1] = string.format('  Files: %d', file_count)
    lines[#lines + 1] = string.format('  Duration: %ds', os.time() - session.started_at)
  else
    lines[#lines + 1] = '  No active session'
  end

  vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
end

function M.statusline()
  local ok, socket = pcall(require, 'blast.socket')
  if ok and socket.is_connected() then
    return '\xF0\x9F\x9A\x80'
  end
  return '\xF0\x9F\x92\xA5'
end

function M.ping()
  local socket = require 'blast.socket'

  local ok, err = socket.ping()
  if ok then
    vim.notify('[blast.nvim] pong!', vim.log.levels.INFO)
  else
    vim.notify('[blast.nvim] ping failed: ' .. (err or 'unknown'), vim.log.levels.ERROR)
  end
end

function M.sync()
  local socket = require 'blast.socket'

  vim.notify('[blast.nvim] syncing...', vim.log.levels.INFO)
  socket.send_sync(function(ok, result)
    if ok then
      vim.notify('[blast.nvim] ' .. result, vim.log.levels.INFO)
    else
      vim.notify('[blast.nvim] sync failed: ' .. (result or 'unknown error'), vim.log.levels.ERROR)
    end
  end)
end

return M
