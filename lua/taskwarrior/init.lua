local M = {}

---@param opts table|nil 사용자 설정 (config.lua defaults 참고)
function M.setup(opts)
  require("taskwarrior.config").setup(opts)
end

function M.open()
  require("taskwarrior.ui").open()
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
