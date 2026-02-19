---@brief [[
--- blast.nvim health check
--- Run with :checkhealth blast
---@brief ]]

local M = {}

function M.check()
  vim.health.start("blast.nvim")

  -- Check Neovim version
  if vim.fn.has("nvim-0.9") == 1 then
    vim.health.ok("Neovim >= 0.9")
  else
    vim.health.error("Neovim >= 0.9 required", { "Upgrade Neovim to 0.9 or later" })
  end

  -- Check glaze.nvim (optional)
  local has_glaze = pcall(require, "glaze")
  if has_glaze then
    vim.health.ok("glaze.nvim found (binary management enabled)")
  else
    vim.health.warn("glaze.nvim not found", {
      "Install glaze.nvim for automatic blastd binary management",
      "See: https://github.com/taigrr/glaze.nvim",
    })
  end

  -- Check blastd binary
  if vim.fn.executable("blastd") == 1 then
    local version = vim.fn.system("blastd --version 2>/dev/null"):gsub("%s+$", "")
    if version ~= "" then
      vim.health.ok("blastd found: " .. version)
    else
      vim.health.ok("blastd found")
    end
  else
    vim.health.error("blastd not found", {
      "Install with :GlazeInstall blastd (if glaze.nvim is installed)",
      "Or manually: go install github.com/taigrr/blastd@latest",
      "See: https://github.com/taigrr/blastd",
    })
  end

  -- Check socket
  local config = require("blast").config
  local sock_path = vim.fn.expand(config.socket_path)
  if vim.uv.fs_stat(sock_path) then
    vim.health.ok("blastd socket found: " .. sock_path)
  else
    vim.health.info("blastd socket not found (daemon may not be running): " .. sock_path)
  end

  -- Check config file
  local config_path = vim.fn.expand("~/.config/blastd/config.toml")
  if vim.uv.fs_stat(config_path) then
    vim.health.ok("blastd config found: " .. config_path)
  else
    vim.health.warn("blastd config not found: " .. config_path, {
      "Create config with your API token from https://www.nvimblast.com/settings",
    })
  end
end

return M
