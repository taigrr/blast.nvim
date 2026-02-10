local M = {}

local socket = require("blast.socket")
local tracker = require("blast.tracker")

M.config = {
  socket_path = vim.fn.expand("~/.local/share/blastd/blastd.sock"),
  idle_timeout = 120, -- seconds of no activity before ending a session
  debounce_ms = 1000, -- debounce activity events
  debug = false,
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  socket.setup(M.config)
  tracker.setup(M.config)

  if M.config.debug then
    vim.notify("[blast.nvim] initialized", vim.log.levels.INFO)
  end
end

function M.status()
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
  local ok, err = socket.ping()
  if ok then
    vim.notify("[blast.nvim] pong!", vim.log.levels.INFO)
  else
    vim.notify("[blast.nvim] ping failed: " .. (err or "unknown"), vim.log.levels.ERROR)
  end
end

return M
