local config = require("taskwarrior.config")

local M = {}

---taskwarrior-tui 를 플로팅 터미널로 연다 (lazygit.nvim 방식)
function M.open()
  local bin = config.options.tui_bin
  if vim.fn.executable(bin) ~= 1 then
    vim.notify("taskwarrior: '" .. bin .. "' 실행 파일을 찾을 수 없습니다 (brew install taskwarrior-tui)", vim.log.levels.ERROR)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  local width = math.floor(vim.o.columns * 0.9)
  local height = math.floor(vim.o.lines * 0.85)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = config.options.window.border,
    title = " taskwarrior-tui ",
    title_pos = "center",
  })

  local function on_exit()
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end)
  end

  if vim.fn.has("nvim-0.11") == 1 then
    vim.fn.jobstart({ bin }, { term = true, on_exit = on_exit })
  else
    vim.fn.termopen({ bin }, { on_exit = on_exit })
  end
  vim.cmd.startinsert()
end

---`task calendar` 출력(마감일 색 표시)을 플로팅 터미널로 보여준다. q/<Esc> 로 닫기
function M.calendar()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  local win = require("taskwarrior.util").open_float(buf, 80, 14, " task calendar ")

  local cmd = { config.options.task_bin, "calendar" }
  if vim.fn.has("nvim-0.11") == 1 then
    vim.fn.jobstart(cmd, { term = true })
  else
    vim.fn.termopen(cmd)
  end
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end, { buffer = buf, nowait = true, silent = true })
  end
end

return M
