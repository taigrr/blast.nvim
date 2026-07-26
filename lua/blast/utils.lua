local M = {}

local project_cache = {}

local function is_root(dir)
  if dir == '/' or dir == '' then
    return true
  end
  if dir:match '^%a:[/\\]?$' then
    return true
  end
  return false
end

local function parse_blast_config(content)
  local parsed = {
    private = false,
  }

  for line in content:gmatch '[^\r\n]+' do
    local stripped = line:match '^%s*(.-)%s*$'
    if stripped ~= '' and not stripped:match '^#' then
      local key, raw_value = stripped:match '^([%w_%-]+)%s*=%s*(.-)%s*$'
      if key and raw_value then
        local double_quoted = raw_value:match '^"([^"]*)"'
        local single_quoted = raw_value:match "^'([^']*)'"

        if key == 'name' then
          local name = double_quoted or single_quoted
          if name and name ~= '' then
            parsed.name = name
          end
        elseif key == 'private' and raw_value:match '^true%f[%W]' then
          parsed.private = true
        end
      end
    end
  end

  return parsed
end

function M.get_project_info(filepath)
  local dir = vim.fn.fnamemodify(filepath, ':h')
  if project_cache[dir] then
    local c = project_cache[dir]
    return c.project, c.git_remote, c.private, c.git_branch
  end

  local project = nil
  local git_remote = nil
  local git_branch = nil
  local private = false

  local git_dir = M.find_dir_upward('.git', dir)
  local git_root = git_dir and vim.fn.fnamemodify(git_dir, ':h') or nil

  local blast_config = M.find_file_upward('.blast.toml', dir, git_root)
  if blast_config then
    local config_content = M.read_file(blast_config)
    if config_content then
      local blast_config_data = parse_blast_config(config_content)
      if blast_config_data.name then
        project = blast_config_data.name
      end
      private = blast_config_data.private
    end
  end

  if git_root then
    if not project then
      project = vim.fn.fnamemodify(git_root, ':t')
    end

    local remote = M.exec('git -C ' .. vim.fn.shellescape(git_root) .. ' remote get-url origin 2>/dev/null')
    if remote and remote ~= '' then
      git_remote = vim.trim(remote)
    end

    local branch = M.exec('git -C ' .. vim.fn.shellescape(git_root) .. ' rev-parse --abbrev-ref HEAD 2>/dev/null')
    if branch and branch ~= '' then
      git_branch = vim.trim(branch)
    end
  end

  if not project then
    project = vim.fn.fnamemodify(dir, ':t')
  end

  project_cache[dir] = {
    project = project,
    git_remote = git_remote,
    git_branch = git_branch,
    private = private,
  }

  return project, git_remote, private, git_branch
end

function M.find_file_upward(filename, start_dir, stop_dir)
  local dir = start_dir
  while not is_root(dir) do
    local path = dir .. '/' .. filename
    if vim.fn.filereadable(path) == 1 then
      return path
    end
    if stop_dir and dir == stop_dir then
      break
    end
    local parent = vim.fn.fnamemodify(dir, ':h')
    if parent == dir then
      break
    end
    dir = parent
  end
  -- Check root directory (the while loop skips it)
  if is_root(dir) then
    local path = dir .. '/' .. filename
    if vim.fn.filereadable(path) == 1 then
      return path
    end
  end
  return nil
end

function M.find_dir_upward(dirname, start_dir)
  local dir = start_dir
  while not is_root(dir) do
    local path = dir .. '/' .. dirname
    if vim.fn.isdirectory(path) == 1 then
      return path
    end
    local parent = vim.fn.fnamemodify(dir, ':h')
    if parent == dir then
      break
    end
    dir = parent
  end
  if not is_root(dir) then
    return nil
  end
  local path = dir .. '/' .. dirname
  if vim.fn.isdirectory(path) == 1 then
    return path
  end
  return nil
end

function M.get_git_root(filepath)
  local dir = vim.fn.fnamemodify(filepath, ':h')
  local git_dir = M.find_dir_upward('.git', dir)
  if git_dir then
    return vim.fn.fnamemodify(git_dir, ':h')
  end
  return nil
end

function M.read_file(path)
  local file = io.open(path, 'r')
  if not file then
    return nil
  end
  local content = file:read '*a'
  file:close()
  return content
end

function M.exec(cmd)
  local handle = io.popen(cmd)
  if not handle then
    return nil
  end
  local result = handle:read '*a'
  handle:close()
  return result
end

function M.find_blastd_bin()
  -- Check glaze.nvim first, then fall back to PATH
  local glaze_ok, glaze = pcall(require, 'glaze')
  if glaze_ok and glaze.bin_path then
    local bin = glaze.bin_path 'blastd'
    if bin and bin ~= '' then
      return bin
    end
  end
  local bin = vim.fn.exepath 'blastd'
  if bin and bin ~= '' then
    return bin
  end
  return nil
end

function M.clear_project_cache()
  project_cache = {}
end

M._parse_blast_config = parse_blast_config

return M
