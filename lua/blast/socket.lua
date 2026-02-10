local M = {}

local uv = vim.uv or vim.loop
local config = {}
local client = nil

function M.setup(cfg)
  config = cfg
end

local function connect()
  if client then
    return true
  end

  local sock = uv.new_pipe(false)
  local ok, err = pcall(function()
    sock:connect(config.socket_path)
  end)

  if not ok then
    if config.debug then
      vim.schedule(function()
        vim.notify("[blast.nvim] socket connect failed: " .. tostring(err), vim.log.levels.WARN)
      end)
    end
    sock:close()
    return false
  end

  client = sock
  return true
end

function M.is_connected()
  return client ~= nil and not client:is_closing()
end

function M.disconnect()
  if client then
    client:close()
    client = nil
  end
end

function M.send(data)
  if not connect() then
    return false, "not connected"
  end

  local json = vim.json.encode(data) .. "\n"

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
  return M.send({ type = "ping" })
end

function M.send_activity(activity)
  return M.send({
    type = "activity",
    data = activity,
  })
end

return M
