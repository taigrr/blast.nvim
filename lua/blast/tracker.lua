local M = {}

local socket = require("blast.socket")
local utils = require("blast.utils")

local config = {}
local current_session = nil
local last_activity = 0
local debounce_timer = nil
local idle_timer = nil

-- Metrics tracking
local action_count = 0
local word_count = 0
local session_start_words = 0

function M.setup(cfg)
  config = cfg

  -- Set up autocommands
  local group = vim.api.nvim_create_augroup("BlastTracker", { clear = true })

  -- Track buffer activity
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
    group = group,
    callback = function()
      M.on_buffer_activity()
    end,
  })

  -- Track text changes
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group,
    callback = function()
      M.on_text_change()
    end,
  })

  -- Track commands/actions
  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = group,
    callback = function()
      action_count = action_count + 1
    end,
  })

  -- Track on vim leave
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      M.end_session()
    end,
  })
end

function M.get_session()
  return current_session
end

function M.on_buffer_activity()
  local now = os.time()
  last_activity = now

  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local filetype = vim.bo[bufnr].filetype

  -- Skip non-file buffers
  if filepath == "" or vim.bo[bufnr].buftype ~= "" then
    return
  end

  local project, git_remote = utils.get_project_info(filepath)

  -- Check if we need to start a new session
  if not current_session or current_session.project ~= project then
    M.end_session()
    M.start_session(project, git_remote, filetype)
  elseif current_session.filetype ~= filetype then
    current_session.filetype = filetype
  end

  M.reset_idle_timer()
end

function M.on_text_change()
  last_activity = os.time()
  action_count = action_count + 1

  -- Count words for WPM calculation
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local text = table.concat(lines, " ")
  word_count = select(2, text:gsub("%S+", ""))

  M.reset_idle_timer()
end

function M.start_session(project, git_remote, filetype)
  current_session = {
    project = project,
    git_remote = git_remote,
    filetype = filetype,
    started_at = os.time(),
  }

  action_count = 0
  session_start_words = word_count

  if config.debug then
    vim.schedule(function()
      vim.notify(string.format("[blast.nvim] started session: %s", project or "unknown"), vim.log.levels.DEBUG)
    end)
  end
end

function M.end_session()
  if not current_session then
    return
  end

  local now = os.time()
  local duration = now - current_session.started_at

  -- Only send if session was at least 10 seconds
  if duration >= 10 then
    local minutes = duration / 60
    local apm = minutes > 0 and (action_count / minutes) or 0
    local wpm = minutes > 0 and ((word_count - session_start_words) / minutes) or 0

    local activity = {
      project = current_session.project,
      git_remote = current_session.git_remote,
      started_at = os.date("!%Y-%m-%dT%H:%M:%SZ", current_session.started_at),
      ended_at = os.date("!%Y-%m-%dT%H:%M:%SZ", now),
      filetype = current_session.filetype,
      actions_per_minute = math.floor(apm * 10) / 10,
      words_per_minute = math.floor(wpm * 10) / 10,
    }

    socket.send_activity(activity)

    if config.debug then
      vim.schedule(function()
        vim.notify(
          string.format("[blast.nvim] ended session: %s (%ds, %.1f APM)", current_session.project or "unknown", duration, apm),
          vim.log.levels.DEBUG
        )
      end)
    end
  end

  current_session = nil
  action_count = 0
end

function M.reset_idle_timer()
  if idle_timer then
    idle_timer:stop()
  end

  idle_timer = vim.defer_fn(function()
    if current_session and (os.time() - last_activity) >= config.idle_timeout then
      M.end_session()
    end
  end, config.idle_timeout * 1000)
end

return M
