if vim.g.loaded_blast then
  return
end
vim.g.loaded_blast = true

vim.api.nvim_create_user_command("BlastStatus", function()
  require("blast").status()
end, { desc = "Show Blast status" })

vim.api.nvim_create_user_command("BlastPing", function()
  require("blast").ping()
end, { desc = "Ping blastd daemon" })
