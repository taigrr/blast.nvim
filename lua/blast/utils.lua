local M = {}

-- Cache for project info
local project_cache = {}

function M.get_project_info(filepath)
  -- Check cache first
  local dir = vim.fn.fnamemodify(filepath, ":h")
  if project_cache[dir] then
    return project_cache[dir].project, project_cache[dir].git_remote
  end

  local project = nil
  local git_remote = nil

  -- Try to find .blast.toml for project name override
  local blast_config = M.find_file_upward(".blast.toml", dir)
  if blast_config then
    local config_content = M.read_file(blast_config)
    if config_content then
      local name = config_content:match('name%s*=%s*"([^"]+)"')
      if name then
        project = name
      end
    end
  end

  -- Try to get git info
  local git_dir = M.find_dir_upward(".git", dir)
  if git_dir then
    -- Get project name from git directory
    if not project then
      project = vim.fn.fnamemodify(vim.fn.fnamemodify(git_dir, ":h"), ":t")
    end

    -- Get remote URL
    local remote = M.exec("git -C " .. vim.fn.shellescape(vim.fn.fnamemodify(git_dir, ":h")) .. " remote get-url origin 2>/dev/null")
    if remote and remote ~= "" then
      git_remote = vim.trim(remote)
    end
  end

  -- Fallback to directory name
  if not project then
    project = vim.fn.fnamemodify(dir, ":t")
  end

  -- Cache the result
  project_cache[dir] = {
    project = project,
    git_remote = git_remote,
  }

  return project, git_remote
end

function M.find_file_upward(filename, start_dir)
  local dir = start_dir
  while dir ~= "/" and dir ~= "" do
    local path = dir .. "/" .. filename
    if vim.fn.filereadable(path) == 1 then
      return path
    end
    dir = vim.fn.fnamemodify(dir, ":h")
  end
  return nil
end

function M.find_dir_upward(dirname, start_dir)
  local dir = start_dir
  while dir ~= "/" and dir ~= "" do
    local path = dir .. "/" .. dirname
    if vim.fn.isdirectory(path) == 1 then
      return path
    end
    dir = vim.fn.fnamemodify(dir, ":h")
  end
  return nil
end

function M.read_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  return content
end

function M.exec(cmd)
  local handle = io.popen(cmd)
  if not handle then
    return nil
  end
  local result = handle:read("*a")
  handle:close()
  return result
end

return M
