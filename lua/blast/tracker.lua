local M = {}

local uv = vim.uv or vim.loop
local socket = require("blast.socket")
local utils = require("blast.utils")

local config = {}
local current_session = nil
local last_activity = 0
local debounce_timer = nil
local idle_timer = nil

local action_count = 0
local session_words_added = 0
local last_word_count = 0

function M.setup(cfg)
	config = cfg

	local group = vim.api.nvim_create_augroup("BlastTracker", { clear = true })

	vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
		group = group,
		callback = function()
			M.on_buffer_activity()
		end,
	})

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = group,
		callback = function()
			M.on_text_change()
		end,
	})

	vim.api.nvim_create_autocmd("CmdlineLeave", {
		group = group,
		callback = function()
			action_count = action_count + 1
		end,
	})

	vim.api.nvim_create_autocmd({ "TermOpen", "TermEnter" }, {
		group = group,
		callback = function()
			M.on_terminal_activity()
		end,
	})

	vim.api.nvim_create_autocmd("VimLeavePre", {
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

local function count_words(bufnr)
	local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
	if not ok then
		return 0
	end
	local total = 0
	for _, line in ipairs(lines) do
		for _ in line:gmatch("%S+") do
			total = total + 1
		end
	end
	return total
end

function M.on_buffer_activity()
	local bufnr = vim.api.nvim_get_current_buf()
	local filepath = vim.api.nvim_buf_get_name(bufnr)
	local filetype = vim.bo[bufnr].filetype

	if vim.bo[bufnr].buftype == "terminal" then
		M.on_terminal_activity()
		return
	end

	if filepath == "" or vim.bo[bufnr].buftype ~= "" then
		return
	end

	last_activity = os.time()
	local project, git_remote = utils.get_project_info(filepath)

	if not current_session or current_session.project ~= project then
		M.end_session()
		M.start_session(project, git_remote, filetype)
	elseif current_session.filetype ~= filetype then
		current_session.filetype = filetype
	end

	last_word_count = count_words(bufnr)

	M.reset_idle_timer()
end

function M.on_text_change()
	last_activity = os.time()
	action_count = action_count + 1

	if debounce_timer then
		debounce_timer:stop()
	else
		debounce_timer = uv.new_timer()
	end

	debounce_timer:start(
		config.debounce_ms,
		0,
		vim.schedule_wrap(function()
			local bufnr = vim.api.nvim_get_current_buf()
			if not vim.api.nvim_buf_is_valid(bufnr) then
				return
			end
			local new_count = count_words(bufnr)
			local delta = new_count - last_word_count
			if delta > 0 then
				session_words_added = session_words_added + delta
			end
			last_word_count = new_count
		end)
	)

	M.reset_idle_timer()
end

function M.on_terminal_activity()
	last_activity = os.time()
	action_count = action_count + 1
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
	session_words_added = 0
	last_word_count = 0

	local bufnr = vim.api.nvim_get_current_buf()
	if vim.api.nvim_buf_is_valid(bufnr) then
		last_word_count = count_words(bufnr)
	end

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

	local session = current_session
	current_session = nil

	local now = os.time()
	local duration = now - session.started_at

	if duration < 10 then
		action_count = 0
		session_words_added = 0
		last_word_count = 0
		return
	end

	local minutes = duration / 60
	local apm = minutes > 0 and (action_count / minutes) or 0
	local wpm = minutes > 0 and (session_words_added / minutes) or 0

	local activity = {
		project = session.project,
		git_remote = session.git_remote,
		started_at = os.date("!%Y-%m-%dT%H:%M:%SZ", session.started_at),
		ended_at = os.date("!%Y-%m-%dT%H:%M:%SZ", now),
		filetype = session.filetype,
		actions_per_minute = math.floor(apm * 10) / 10,
		words_per_minute = math.floor(wpm * 10) / 10,
		editor = "neovim",
	}

	socket.send_activity(activity)

	if config.debug then
		local project_name = session.project or "unknown"
		vim.schedule(function()
			vim.notify(
				string.format("[blast.nvim] ended session: %s (%ds, %.1f APM)", project_name, duration, apm),
				vim.log.levels.DEBUG
			)
		end)
	end

	action_count = 0
	session_words_added = 0
	last_word_count = 0
end

function M.reset_idle_timer()
	if idle_timer then
		idle_timer:stop()
	else
		idle_timer = uv.new_timer()
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
