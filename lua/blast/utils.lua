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

function M.get_project_info(filepath)
  local dir = vim.fn.fnamemodify(filepath, ':h')
  if project_cache[dir] then
    return project_cache[dir].project, project_cache[dir].git_remote
  end

  local project = nil
  local git_remote = nil

  local blast_config = M.find_file_upward('.blast.toml', dir)
  if blast_config then
    local config_content = M.read_file(blast_config)
    if config_content then
      local name = config_content:match 'name%s*=%s*"([^"]+)"'
      if name then
        project = name
      end
    end
  end

  local git_dir = M.find_dir_upward('.git', dir)
  if git_dir then
    if not project then
      project = vim.fn.fnamemodify(vim.fn.fnamemodify(git_dir, ':h'), ':t')
    end

    local remote =
      M.exec('git -C ' .. vim.fn.shellescape(vim.fn.fnamemodify(git_dir, ':h')) .. ' remote get-url origin 2>/dev/null')
    if remote and remote ~= '' then
      git_remote = vim.trim(remote)
    end
  end

  if not project then
    project = vim.fn.fnamemodify(dir, ':t')
  end

  project_cache[dir] = {
    project = project,
    git_remote = git_remote,
  }

  return project, git_remote
end

function M.find_file_upward(filename, start_dir)
  local dir = start_dir
  while not is_root(dir) do
    local path = dir .. '/' .. filename
    if vim.fn.filereadable(path) == 1 then
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
  local path = dir .. '/' .. filename
  if vim.fn.filereadable(path) == 1 then
    return path
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

return M
