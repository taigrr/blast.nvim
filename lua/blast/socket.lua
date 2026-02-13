local M = {}

local uv = vim.uv or vim.loop
local config = {}
local client = nil
local ping_timer = nil
local blastd_job = nil

local function ensure_blastd()
  local sock_path = config.socket_path
  if not sock_path then
    return
  end
  if uv.fs_stat(sock_path) then
    return
  end

  local bin = vim.fn.exepath 'blastd'
  if bin == '' then
    if config.debug then
      vim.schedule(function()
        vim.notify('[blast.nvim] blastd not found in PATH', vim.log.levels.WARN)
      end)
    end
    return
  end

  local stdout = uv.new_pipe(false)
  local stderr = uv.new_pipe(false)
  if not stdout or not stderr then
    if stdout then
      stdout:close()
    end
    if stderr then
      stderr:close()
    end
    return
  end

  blastd_job = uv.spawn(bin, {
    args = {},
    stdio = { nil, stdout, stderr },
    detached = true,
  }, function(code, signal)
    blastd_job = nil
    if stdout then
      stdout:close()
    end
    if stderr then
      stderr:close()
    end
    if config.debug then
      vim.schedule(function()
        vim.notify(
          string.format('[blast.nvim] blastd exited (code=%s, signal=%s)', tostring(code), tostring(signal)),
          vim.log.levels.DEBUG
        )
      end)
    end
  end)

  if not blastd_job then
    if config.debug then
      vim.schedule(function()
        vim.notify('[blast.nvim] failed to spawn blastd', vim.log.levels.WARN)
      end)
    end
    return
  end

  if stdout then
    stdout:read_start(function() end)
  end
  if stderr then
    stderr:read_start(function() end)
  end

  uv.unref(blastd_job)

  local wait_ms = 500
  local elapsed = 0
  local check_timer = uv.new_timer()
  if not check_timer then
    return
  end
  check_timer:start(50, 50, function()
    elapsed = elapsed + 50
    if uv.fs_stat(sock_path) or elapsed >= wait_ms then
      check_timer:stop()
      check_timer:close()
    end
  end)
  uv.run 'once'
  vim.wait(wait_ms, function()
    return uv.fs_stat(sock_path) ~= nil
  end, 50)
end

local function connect()
  if client then
    local ok, closing = pcall(client.is_closing, client)
    if ok and not closing then
      return true
    end
    client = nil
  end

  ensure_blastd()

  if not config.socket_path then
    return false
  end

  local sock = uv.new_pipe(false)
  if not sock then
    return false
  end
  local connected = nil
  local ok, err = pcall(function()
    sock:connect(config.socket_path, function(connect_err)
      connected = not connect_err
      if connect_err then
        if config.debug then
          vim.schedule(function()
            vim.notify('[blast.nvim] socket connect failed: ' .. tostring(connect_err), vim.log.levels.WARN)
          end)
        end
        pcall(function()
          sock:close()
        end)
      end
    end)
  end)

  if not ok then
    if config.debug then
      vim.schedule(function()
        vim.notify('[blast.nvim] socket connect error: ' .. tostring(err), vim.log.levels.WARN)
      end)
    end
    pcall(function()
      sock:close()
    end)
    return false
  end

  vim.wait(1000, function()
    return connected ~= nil
  end, 10)

  if connected then
    client = sock
    return true
  else
    client = nil
    return false
  end
end

function M.setup(cfg)
  config = cfg
  connect()
end

function M.is_connected()
  if not client then
    return false
  end
  local ok, closing = pcall(client.is_closing, client)
  return ok and not closing
end

function M.disconnect()
  if client then
    pcall(function()
      client:close()
    end)
    client = nil
  end
end

function M.send(data)
  if not connect() then
    return false, 'not connected'
  end

  local json = vim.json.encode(data) .. '\n'

  local ok, err = pcall(function()
    client:write(json)
  end)

  if not ok then
    M.disconnect()
    return false, err
  end

  return true
end

function M.ping()
  return M.send { type = 'ping' }
end

function M.send_activity(activity)
  return M.send {
    type = 'activity',
    data = activity,
  }
end

function M.start_keepalive()
  M.stop_keepalive()

  ping_timer = uv.new_timer()
  if not ping_timer then
    return
  end
  ping_timer:start(
    10000,
    10000,
    vim.schedule_wrap(function()
      if M.is_connected() then
        M.ping()
      end
    end)
  )
end

function M.stop_keepalive()
  if ping_timer then
    ping_timer:stop()
    ping_timer:close()
    ping_timer = nil
  end
end

function M.shutdown()
  M.stop_keepalive()
  M.disconnect()
end

return M
