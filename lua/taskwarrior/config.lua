local M = {}

M.defaults = {
  -- taskwarrior 실행 파일 경로
  task_bin = "task",
  -- taskwarrior-tui 실행 파일 경로 (선택)
  tui_bin = "taskwarrior-tui",
  -- 기본 필터 (task CLI 필터 문법 그대로)
  filter = "status:pending",
  window = {
    width = 0.85, -- editor 대비 비율
    height = 0.8,
    border = "rounded",
    title = " Taskwarrior ",
  },
  confirm = {
    done = false,
    delete = true,
  },
  keymaps = {
    add = "a",
    done = "d",
    delete = "x",
    modify = "m",
    toggle_start = "s",
    priority = "p",
    annotate = "A",
    undo = "u",
    filter = "f",
    refresh = "r",
    detail = "<CR>",
    tui = "t",
    help = "?",
    quit = "q",
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
