if vim.g.loaded_taskwarrior_nvim then
  return
end
vim.g.loaded_taskwarrior_nvim = true

vim.api.nvim_create_user_command("TaskWarrior", function()
  require("taskwarrior").toggle()
end, { desc = "Toggle Taskwarrior floating window" })

vim.api.nvim_create_user_command("TaskWarriorAgenda", function()
  require("taskwarrior").agenda()
end, { desc = "Open Taskwarrior agenda (tasks grouped by due date)" })

vim.api.nvim_create_user_command("TaskWarriorCalendar", function()
  require("taskwarrior").calendar()
end, { desc = "Open Taskwarrior month calendar" })

vim.api.nvim_create_user_command("TaskWarriorCalendarRaw", function()
  require("taskwarrior").calendar_raw()
end, { desc = "Show `task calendar` output in a floating terminal" })

vim.api.nvim_create_user_command("TaskWarriorTui", function()
  require("taskwarrior").tui()
end, { desc = "Open taskwarrior-tui in a floating terminal" })
