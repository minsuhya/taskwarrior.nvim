local M = {}

---@param opts table|nil 사용자 설정 (config.lua defaults 참고)
function M.setup(opts)
  require("taskwarrior.config").setup(opts)
end

---@param opts table|nil { view = "list"|"agenda", filter = string }
function M.open(opts)
  require("taskwarrior.ui").open(opts)
end

function M.agenda()
  require("taskwarrior.ui").open({ view = "agenda", filter = require("taskwarrior.config").options.filter })
end

function M.calendar()
  require("taskwarrior.calendar").open()
end

function M.calendar_raw()
  require("taskwarrior.tui").calendar()
end

function M.close()
  require("taskwarrior.ui").close()
end

function M.toggle()
  require("taskwarrior.ui").toggle()
end

function M.tui()
  require("taskwarrior.tui").open()
end

return M
