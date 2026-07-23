if vim.g.loaded_taskwarrior_nvim then
  return
end
vim.g.loaded_taskwarrior_nvim = true

vim.api.nvim_create_user_command("TaskWarrior", function()
  require("taskwarrior").toggle()
end, { desc = "Toggle Taskwarrior floating window" })

vim.api.nvim_create_user_command("TaskWarriorTui", function()
  require("taskwarrior").tui()
end, { desc = "Open taskwarrior-tui in a floating terminal" })
