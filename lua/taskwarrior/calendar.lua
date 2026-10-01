local api = vim.api
local cli = require("taskwarrior.cli")
local config = require("taskwarrior.config")
local util = require("taskwarrior.util")

local M = {}

local ns = api.nvim_create_namespace("taskwarrior_nvim_calendar")

local CELL = 5 -- 날짜 칸 표시 폭 (" 12³ " 형태)
local WIDTH = CELL * 7 + 2

local state = {
  buf = nil,
  win = nil,
  sel = nil, -- 선택 날짜 { year, month, day }
  buckets = {}, -- "YYYY-MM-DD" -> tasks
}

local weekday_names = { "일", "월", "화", "수", "목", "금", "토" }
local count_marks = { "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹" }

local function key_of(y, m, d)
  return os.date("%Y-%m-%d", os.time({ year = y, month = m, day = d, hour = 12 }))
end

-- 날짜 정규화 (day = 0, 32 같은 값도 처리)
local function norm(y, m, d)
  local t = os.date("*t", os.time({ year = y, month = m, day = d, hour = 12 }))
  return { year = t.year, month = t.month, day = t.day }
end

local function weekstart_monday()
  local ws = config.options.calendar.weekstart
  if not ws then
    local ok, out = cli.run({ "_get", "rc.weekstart" })
    ws = ok and vim.trim(out) or "sunday"
    config.options.calendar.weekstart = ws -- 한 번만 조회
  end
  return ws:lower() == "monday"
end

local function load()
  local tasks, err = cli.export("status:pending due.any:")
  if not tasks then
    vim.notify("taskwarrior: " .. vim.trim(err or "export 실패"), vim.log.levels.ERROR)
    tasks = {}
  end
  state.buckets = {}
  for _, t in ipairs(tasks) do
    local key = util.due_key(t)
    if key then
      state.buckets[key] = state.buckets[key] or {}
      table.insert(state.buckets[key], t)
    end
  end
  for _, list in pairs(state.buckets) do
    table.sort(list, function(a, b)
      return (a.urgency or 0) > (b.urgency or 0)
    end)
  end
end

local function render()
  if not (state.buf and api.nvim_buf_is_valid(state.buf)) then
    return
  end
  local lines, hls = {}, {}
  local function push(segs)
    util.push(lines, hls, segs)
  end

  local sel = state.sel
  local today = os.date("%Y-%m-%d")
  local monday = weekstart_monday()

  local title = string.format("%d년 %d월", sel.year, sel.month)
  local left = math.floor((WIDTH - vim.fn.strdisplaywidth(title)) / 2)
  push({ { string.rep(" ", left) .. title, "TaskwarriorHeader" } })

  local head = { { " " } }
  for i = 0, 6 do
    local wd = (i + (monday and 1 or 0)) % 7
    head[#head + 1] = { string.rep(" ", CELL - 2) .. weekday_names[wd + 1], (wd == 0 or wd == 6) and "TaskwarriorWeekend" or "TaskwarriorColumns" }
  end
  push(head)

  local first_wd = tonumber(os.date("%w", os.time({ year = sel.year, month = sel.month, day = 1, hour = 12 })))
  local offset = monday and (first_wd + 6) % 7 or first_wd
  local last_day = norm(sel.year, sel.month + 1, 0).day

  local day = 1 - offset
  while day <= last_day do
    local segs = { { " " } }
    for col = 0, 6 do
      if day < 1 or day > last_day then
        segs[#segs + 1] = { string.rep(" ", CELL) }
      else
        local key = key_of(sel.year, sel.month, day)
        local tasks = state.buckets[key]
        local n = tasks and #tasks or 0
        local mark = n == 0 and " " or (count_marks[n] or "⁺")
        local group
        if day == sel.day then
          group = "TaskwarriorSelected"
        elseif key == today then
          group = "TaskwarriorToday"
        elseif n > 0 then
          group = key < today and "TaskwarriorOverdue" or "TaskwarriorDueSoon"
        else
          local wd = (col + (monday and 1 or 0)) % 7
          group = (wd == 0 or wd == 6) and "TaskwarriorWeekend" or nil
        end
        segs[#segs + 1] = { string.format(" %2d%s ", day, mark), group }
      end
      day = day + 1
    end
    push(segs)
  end

  -- 선택 날짜의 태스크 목록
  local sel_key = key_of(sel.year, sel.month, sel.day)
  local wd = tonumber(os.date("%w", os.time({ year = sel.year, month = sel.month, day = sel.day, hour = 12 })))
  push({ { "" } })
  push({ { string.format(" %s (%s)", sel_key, weekday_names[wd + 1]), "TaskwarriorHeader" } })
  local tasks = state.buckets[sel_key] or {}
  for _, t in ipairs(tasks) do
    local pr = t.priority or ""
    push({
      { " " },
      { util.pad(tostring(t.id ~= 0 and t.id or t.uuid:sub(1, 4)), 4), "TaskwarriorId" },
      { util.pad(pr, 1), pr ~= "" and ("TaskwarriorPriority" .. pr) or nil },
      { util.pad(t.project or "", 13), "TaskwarriorProject" },
      { t.description or "", t.start and "TaskwarriorActive" or nil },
    })
  end
  if #tasks == 0 then
    push({ { "  (마감 태스크 없음 — 'a' 로 이 날짜에 추가)", "TaskwarriorColumns" } })
  end
  push({ { "" } })
  push({ { " hjkl 이동 · [ ] 달 · . 오늘 · <CR> 목록 · a 추가 · v 일정 · ? 도움말", "TaskwarriorColumns" } })

  util.set_lines(state.buf, ns, lines, hls)
  -- 선택 날짜의 태스크 수에 맞춰 창 높이 조절
  if state.win and api.nvim_win_is_valid(state.win) then
    api.nvim_win_set_height(state.win, math.min(#lines, vim.o.lines - 4))
  end
end

local function move(days, months)
  local s = state.sel
  if months then
    local last = norm(s.year, s.month + months + 1, 0).day
    state.sel = norm(s.year, s.month + months, math.min(s.day, last))
  else
    state.sel = norm(s.year, s.month, s.day + days)
  end
  render()
end

local function sel_key()
  return key_of(state.sel.year, state.sel.month, state.sel.day)
end

local function refresh()
  load()
  render()
end

function M.show_help()
  local items = {
    { "h / l", "하루 이동" },
    { "j / k", "일주일 이동" },
    { "[ / ]", "이전 / 다음 달 (H / L 도 가능)" },
    { ".", "오늘로 이동" },
    { "<CR>", "선택 날짜의 태스크를 목록 화면에서 열기 (완료·수정 등)" },
    { "a", "선택 날짜를 due 로 태스크 추가" },
    { "v", "주간 일정(agenda) 화면 열기" },
    { "r", "새로고침" },
    { "q / <Esc>", "닫기" },
  }
  local lines = {}
  for _, item in ipairs(items) do
    lines[#lines + 1] = string.format("  %-10s %s", item[1], item[2])
  end
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  local win = util.open_float(buf, 64, #lines, " Calendar keymaps ")
  for _, key in ipairs({ "q", "<Esc>", "?" }) do
    vim.keymap.set("n", key, function()
      if api.nvim_win_is_valid(win) then
        api.nvim_win_close(win, true)
      end
    end, { buffer = buf, nowait = true, silent = true })
  end
end

local function set_keymaps(buf)
  local function map(keys, fn, desc)
    for _, key in ipairs(type(keys) == "table" and keys or { keys }) do
      vim.keymap.set("n", key, fn, { buffer = buf, nowait = true, silent = true, desc = "Taskwarrior calendar: " .. desc })
    end
  end

  map({ "q", "<Esc>" }, M.close, "close")
  map({ "h", "<Left>" }, function() move(-1) end, "previous day")
  map({ "l", "<Right>" }, function() move(1) end, "next day")
  map({ "k", "<Up>" }, function() move(-7) end, "previous week")
  map({ "j", "<Down>" }, function() move(7) end, "next week")
  map({ "[", "H" }, function() move(nil, -1) end, "previous month")
  map({ "]", "L" }, function() move(nil, 1) end, "next month")
  map(".", function()
    local t = os.date("*t")
    state.sel = { year = t.year, month = t.month, day = t.day }
    render()
  end, "today")
  map("r", refresh, "refresh")
  map("?", M.show_help, "help")

  map("a", function()
    local key = sel_key()
    vim.ui.input({ prompt = "task add (due:" .. key .. ") > " }, function(input)
      if not input or vim.trim(input) == "" then
        return
      end
      local args = { "add" }
      for w in input:gmatch("%S+") do
        args[#args + 1] = w
      end
      args[#args + 1] = "due:" .. key
      local ok, out = cli.run(args)
      vim.notify("taskwarrior: " .. (ok and "추가됨" or vim.trim(out)), ok and vim.log.levels.INFO or vim.log.levels.ERROR)
      refresh()
    end)
  end, "add on date")

  map("<CR>", function()
    local key = sel_key()
    M.close()
    require("taskwarrior.ui").open({ view = "list", filter = "status:pending due:" .. key })
  end, "open day in list")

  map("v", function()
    M.close()
    require("taskwarrior.ui").open({ view = "agenda", filter = config.options.filter })
  end, "agenda")
end

function M.open()
  if state.win and api.nvim_win_is_valid(state.win) then
    api.nvim_set_current_win(state.win)
    return
  end
  if vim.fn.executable(config.options.task_bin) ~= 1 then
    vim.notify("taskwarrior: '" .. config.options.task_bin .. "' 실행 파일을 찾을 수 없습니다", vim.log.levels.ERROR)
    return
  end

  require("taskwarrior.ui").ensure_hl()
  local today = os.date("*t")
  state.sel = { year = today.year, month = today.month, day = today.day }

  state.buf = api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].filetype = "taskwarrior-calendar"

  local width = math.max(WIDTH, math.floor(vim.o.columns * 0.5))
  state.win = util.open_float(state.buf, width, math.floor(vim.o.lines * 0.7), " Taskwarrior Calendar ")
  vim.wo[state.win].wrap = false
  vim.wo[state.win].cursorline = false

  set_keymaps(state.buf)
  api.nvim_create_autocmd("BufWipeout", {
    buffer = state.buf,
    callback = function()
      state.buf, state.win = nil, nil
    end,
  })

  refresh()
end

function M.close()
  if state.win and api.nvim_win_is_valid(state.win) then
    api.nvim_win_close(state.win, true)
  end
  state.buf, state.win = nil, nil
end

return M
