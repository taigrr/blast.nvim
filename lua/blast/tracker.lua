local M = {}

local uv = vim.uv or vim.loop
local socket = require 'blast.socket'
local utils = require 'blast.utils'

local config = {}
local current_session = nil
local last_activity = 0
local debounce_timer = nil
local idle_timer = nil
local flush_timer = nil

local current_file = nil
local current_file_entered_at = nil
local file_metrics = {}
local last_word_count = 0
local last_line_count = 0

local ignored_filetypes = {
  NvimTree = true,
}

local function is_ignored_buf(bufnr)
  local ft = vim.bo[bufnr].filetype
  if ignored_filetypes[ft] then
    return true
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name:match ':crush$' or name == 'Crush Logs' then
    return true
  end
  return false
end

local function new_metrics()
  return {
    action_count = 0,
    words_added = 0,
    lines_added = 0,
    lines_removed = 0,
    active_seconds = 0,
  }
end

local function get_file_metrics(filepath, filetype)
  local key = filepath
  if not file_metrics[key] then
    file_metrics[key] = new_metrics()
    file_metrics[key].filetype = filetype
    file_metrics[key].filepath = filepath
  elseif filetype and filetype ~= '' then
    file_metrics[key].filetype = filetype
  end
  return file_metrics[key]
end

local function clock_out_current()
  if current_file and current_file_entered_at then
    local m = file_metrics[current_file]
    if m then
      local elapsed = os.time() - current_file_entered_at
      if elapsed > 0 then
        m.active_seconds = m.active_seconds + elapsed
      end
    end
    current_file_entered_at = nil
  end
end

local function clock_in(filepath)
  current_file = filepath
  current_file_entered_at = os.time()
end

local function count_words(bufnr)
  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
  if not ok then
    return 0
  end
  local total = 0
  for _, line in ipairs(lines) do
    for _ in line:gmatch '%S+' do
      total = total + 1
    end
  end
  return total
end

local function make_relative(filepath)
  if not filepath then
    return filepath
  end
  local git_root = utils.get_git_root(filepath)
  if git_root then
    local rel = filepath:sub(#git_root + 2)
    if rel ~= '' then
      return rel
    end
  end
  return vim.fn.fnamemodify(filepath, ':t')
end

local function build_activities()
  if not current_session then
    return {}
  end

  local session = current_session
  local project_name = session.private and 'private' or session.project
  local remote = session.private and 'private' or session.git_remote
  local branch = session.private and 'private' or session.git_branch
  local now = os.time()
  local activities = {}

  for key, m in pairs(file_metrics) do
    local seconds = m.active_seconds
    if seconds < 1 and m.action_count == 0 then
      goto continue
    end
    if seconds < 1 then
      seconds = 1
    end

    local minutes = seconds / 60
    local apm = minutes > 0 and (m.action_count / minutes) or 0
    local wpm = minutes > 0 and (m.words_added / minutes) or 0

    local filename = nil
    if not session.private then
      filename = make_relative(m.filepath)
    end

    local started_at = now - seconds
    activities[#activities + 1] = {
      key = key,
      payload = {
        project = project_name,
        git_remote = remote,
        git_branch = branch,
        started_at = os.date('!%Y-%m-%dT%H:%M:%SZ', started_at),
        ended_at = os.date('!%Y-%m-%dT%H:%M:%SZ', now),
        filename = filename,
        filetype = m.filetype,
        lines_added = m.lines_added,
        lines_removed = m.lines_removed,
        actions_per_minute = math.floor(apm * 10) / 10,
        words_per_minute = math.floor(wpm * 10) / 10,
        editor = 'neovim',
      },
    }

    ::continue::
  end

  return activities
end

local function reset_flushed_metrics(keys_to_reset)
  for _, key in ipairs(keys_to_reset) do
    local m = file_metrics[key]
    if m then
      m.action_count = 0
      m.words_added = 0
      m.lines_added = 0
      m.lines_removed = 0
      m.active_seconds = 0
    end
  end
end

local function flush()
  if not current_session then
    return
  end

  clock_out_current()

  local activities = build_activities()
  if #activities == 0 then
    if current_file then
      clock_in(current_file)
    end
    return
  end

  local keys = {}
  for _, a in ipairs(activities) do
    keys[#keys + 1] = a.key
    socket.send_activity(a.payload)
  end

  reset_flushed_metrics(keys)

  if current_file then
    clock_in(current_file)
  end

  if config.debug then
    vim.schedule(function()
      vim.notify(
        string.format('[blast.nvim] flushed %d file activities', #activities),
        vim.log.levels.DEBUG
      )
    end)
  end
end

local function start_flush_timer()
  if flush_timer then
    flush_timer:stop()
    flush_timer:close()
  end
  flush_timer = uv.new_timer()
  if not flush_timer then
    return
  end
  flush_timer:start(
    60000,
    60000,
    vim.schedule_wrap(function()
      if current_session then
        flush()
      end
    end)
  )
end

local function stop_flush_timer()
  if flush_timer then
    flush_timer:stop()
    flush_timer:close()
    flush_timer = nil
  end
end

function M.setup(cfg)
  config = cfg

  local group = vim.api.nvim_create_augroup('BlastTracker', { clear = true })

  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost' }, {
    group = group,
    callback = function()
      M.on_buffer_activity()
    end,
  })

  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    group = group,
    callback = function()
      M.on_text_change()
    end,
  })

  vim.api.nvim_create_autocmd('CmdlineLeave', {
    group = group,
    callback = function()
      if current_file then
        local m = file_metrics[current_file]
        if m and not is_ignored_buf(vim.api.nvim_get_current_buf()) then
          m.action_count = m.action_count + 1
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd({ 'TermOpen', 'TermEnter' }, {
    group = group,
    callback = function()
      M.on_terminal_activity()
    end,
  })

  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function()
      M.end_session()
    end,
  })

  vim.defer_fn(function()
    M.on_buffer_activity()
  end, 50)
end

function M.get_session()
  return current_session
end

function M.get_current_file()
  if current_file then
    return file_metrics[current_file]
  end
  return nil
end

function M.get_file_count()
  local count = 0
  for _ in pairs(file_metrics) do
    count = count + 1
  end
  return count
end

function M.on_buffer_activity()
  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  local filetype = vim.bo[bufnr].filetype

  if vim.bo[bufnr].buftype == 'terminal' then
    M.on_terminal_activity()
    return
  end

  if filepath == '' or vim.bo[bufnr].buftype ~= '' then
    return
  end

  last_activity = os.time()
  local project, git_remote, private, git_branch = utils.get_project_info(filepath)

  if not current_session or current_session.project ~= project then
    M.end_session()
    utils.clear_project_cache()
    M.start_session(project, git_remote, filetype, private, git_branch)
  end

  if filepath ~= current_file then
    vim.schedule(function()
      flush()
    end)
    get_file_metrics(filepath, filetype)
    clock_in(filepath)
  end

  last_word_count = count_words(bufnr)
  last_line_count = vim.api.nvim_buf_line_count(bufnr)

  M.reset_idle_timer()
end

function M.on_text_change()
  last_activity = os.time()

  local bufnr = vim.api.nvim_get_current_buf()
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == '' or not current_session then
    return
  end

  local filetype = vim.bo[bufnr].filetype
  local m = get_file_metrics(filepath, filetype)
  if not is_ignored_buf(bufnr) then
    m.action_count = m.action_count + 1
  end

  if filepath ~= current_file then
    clock_out_current()
    clock_in(filepath)
  end

  if debounce_timer then
    debounce_timer:stop()
  else
    debounce_timer = uv.new_timer()
  end

  if not debounce_timer then
    return
  end

  debounce_timer:start(
    config.debounce_ms,
    0,
    vim.schedule_wrap(function()
      local buf = vim.api.nvim_get_current_buf()
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end

      local cur_path = vim.api.nvim_buf_get_name(buf)
      if cur_path ~= filepath then
        return
      end

      if not is_ignored_buf(buf) then
        local new_words = count_words(buf)
        local word_delta = new_words - last_word_count
        if word_delta > 0 then
          m.words_added = m.words_added + word_delta
        end
        last_word_count = new_words

        local new_lines = vim.api.nvim_buf_line_count(buf)
        local line_delta = new_lines - last_line_count
        if line_delta > 0 then
          m.lines_added = m.lines_added + line_delta
        elseif line_delta < 0 then
          m.lines_removed = m.lines_removed - line_delta
        end
        last_line_count = new_lines
      end
    end)
  )

  M.reset_idle_timer()
end

function M.on_terminal_activity()
  last_activity = os.time()
  clock_out_current()
  current_file = nil
  M.reset_idle_timer()
end

function M.start_session(project, git_remote, filetype, private, git_branch)
  current_session = {
    project = project,
    git_remote = git_remote,
    git_branch = git_branch,
    started_at = os.time(),
    private = private or false,
  }

  file_metrics = {}
  current_file = nil
  current_file_entered_at = nil
  last_word_count = 0
  last_line_count = 0

  local bufnr = vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_is_valid(bufnr) then
    local filepath = vim.api.nvim_buf_get_name(bufnr)
    if filepath ~= '' then
      get_file_metrics(filepath, filetype)
      clock_in(filepath)
      last_word_count = count_words(bufnr)
      last_line_count = vim.api.nvim_buf_line_count(bufnr)
    end
  end

  start_flush_timer()

  if config.debug then
    vim.schedule(function()
      vim.notify(string.format('[blast.nvim] started session: %s', project or 'unknown'), vim.log.levels.DEBUG)
    end)
  end
end

function M.end_session()
  if not current_session then
    return
  end

  local session = current_session
  current_session = nil

  stop_flush_timer()

  local now = os.time()
  local session_duration = now - session.started_at

  if session_duration < 10 then
    file_metrics = {}
    current_file = nil
    current_file_entered_at = nil
    last_word_count = 0
    last_line_count = 0
    return
  end

  clock_out_current()

  local activities = build_activities()
  for _, a in ipairs(activities) do
    socket.send_activity(a.payload)
  end

  if config.debug then
    local debug_name = session.project or 'unknown'
    local private_tag = session.private and ' [private]' or ''
    vim.schedule(function()
      vim.notify(
        string.format(
          '[blast.nvim] ended session: %s (%ds, %d files)%s',
          debug_name,
          session_duration,
          #activities,
          private_tag
        ),
        vim.log.levels.DEBUG
      )
    end)
  end

  file_metrics = {}
  current_file = nil
  current_file_entered_at = nil
  last_word_count = 0
  last_line_count = 0
end

function M.reset_idle_timer()
  if idle_timer then
    idle_timer:stop()
  else
    idle_timer = uv.new_timer()
  end

  if not idle_timer then
    return
  end

  idle_timer:start(
    config.idle_timeout * 1000,
    0,
    vim.schedule_wrap(function()
      if current_session and (os.time() - last_activity) >= config.idle_timeout then
        M.end_session()
      end
    end)
  )
end

return M
