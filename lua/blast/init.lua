local M = {}

M.config = {
  socket_path = vim.fn.expand("~/.local/share/blastd/blastd.sock"),
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

  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  local socket = require("blast.socket")
  local tracker = require("blast.tracker")

  socket.setup(M.config)
  tracker.setup(M.config)
  socket.start_keepalive()

  if M.config.debug then
    vim.notify("[blast.nvim] initialized", vim.log.levels.INFO)
  end
end

function M.status()
  local socket = require("blast.socket")
  local tracker = require("blast.tracker")

  local connected = socket.is_connected()
  local session = tracker.get_session()

  local lines = {
    "blast.nvim status:",
    string.format("  Socket: %s", connected and "connected" or "disconnected"),
    string.format("  Socket path: %s", M.config.socket_path),
  }

  if session then
    lines[#lines + 1] = string.format("  Current session: %s", session.project or "unknown")
    lines[#lines + 1] = string.format("  Filetype: %s", session.filetype or "unknown")
    lines[#lines + 1] = string.format("  Duration: %ds", os.time() - session.started_at)
  else
    lines[#lines + 1] = "  No active session"
  end

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

function M.ping()
  local socket = require("blast.socket")

  local ok, err = socket.ping()
  if ok then
    vim.notify("[blast.nvim] pong!", vim.log.levels.INFO)
  else
    vim.notify("[blast.nvim] ping failed: " .. (err or "unknown"), vim.log.levels.ERROR)
  end
end

return M
