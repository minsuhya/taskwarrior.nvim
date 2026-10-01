local api = vim.api
local cli = require("taskwarrior.cli")
local config = require("taskwarrior.config")
local util = require("taskwarrior.util")

local M = {}

local ns = api.nvim_create_namespace("taskwarrior_nvim")

local state = {
  buf = nil,
  win = nil,
  tasks = {},
  line_tasks = {}, -- 화면 line 번호 -> task
  filter = nil,
  view = "list", -- "list" | "agenda"
}

local hl_links = {
  TaskwarriorHeader = "Title",
  TaskwarriorColumns = "Comment",
  TaskwarriorId = "Number",
  TaskwarriorOverdue = "DiagnosticError",
  TaskwarriorDueSoon = "DiagnosticWarn",
  TaskwarriorDue = "Comment",
  TaskwarriorProject = "Directory",
  TaskwarriorTag = "Special",
  TaskwarriorActive = "DiagnosticOk",
  TaskwarriorPriorityH = "DiagnosticError",
  TaskwarriorPriorityM = "DiagnosticWarn",
  TaskwarriorPriorityL = "Comment",
  TaskwarriorWeekend = "Special",
  TaskwarriorToday = "CurSearch",
  TaskwarriorSelected = "Visual",
}

function M.ensure_hl()
  for group, link in pairs(hl_links) do
    api.nvim_set_hl(0, group, { link = link, default = true })
  end
end

local parse_ts, pad = util.parse_ts, util.pad

-- 로컬 날짜 기준 일수 차이 (자정 기준, 시각 무시)
local function day_diff(ts, now)
  local function noon(t)
    local d = os.date("*t", t)
    return os.time({ year = d.year, month = d.month, day = d.day, hour = 12 })
  end
  return math.floor((noon(ts) - noon(now)) / 86400 + 0.5)
end

local function fmt_due(ts, now)
  local days = day_diff(ts, now)
  if days < 0 then
    return days .. "d", "TaskwarriorOverdue"
  elseif days == 0 then
    return "today", ts < now and "TaskwarriorOverdue" or "TaskwarriorDueSoon"
  elseif days <= 3 then
    return days .. "d", "TaskwarriorDueSoon"
  end
  return days .. "d", "TaskwarriorDue"
end

local function task_segs(t, now)
  local segs = { { " " } }
  local id = (t.id and t.id ~= 0) and tostring(t.id) or tostring(t.uuid):sub(1, 4)
  segs[#segs + 1] = { pad(id, 4), "TaskwarriorId" }
  local pr = t.priority or ""
  segs[#segs + 1] = { pad(pr, 1), pr ~= "" and ("TaskwarriorPriority" .. pr) or nil }

  local due, due_hl = "", nil
  if t.due then
    local ts = parse_ts(t.due)
    if ts then
      due, due_hl = fmt_due(ts, now)
    end
  end
  segs[#segs + 1] = { pad(due, 6), due_hl }
  segs[#segs + 1] = { pad(t.project or "", 13), "TaskwarriorProject" }
  segs[#segs + 1] = { t.description or "", t.start and "TaskwarriorActive" or nil }
  if t.tags and #t.tags > 0 then
    segs[#segs + 1] = { "  +" .. table.concat(t.tags, " +"), "TaskwarriorTag" }
  end
  return segs
end

local weekday_names = { "일", "월", "화", "수", "목", "금", "토" }

---due 가 있는 태스크를 날짜별로 묶어 지난 마감 + 오늘부터 agenda.days 일까지 표시
local function render_agenda(lines, hls, push, now)
  local today = os.date("%Y-%m-%d", now)
  local buckets, overdue = {}, {}
  for _, t in ipairs(state.tasks) do
    local key = util.due_key(t)
    if key and key < today then
      overdue[#overdue + 1] = t
    elseif key then
      buckets[key] = buckets[key] or {}
      table.insert(buckets[key], t)
    end
  end
  local by_due = function(a, b)
    return a.due < b.due
  end

  local function section(title, tasks, group)
    push({ { " " .. title, group }, { string.format("  (%d)", #tasks), "TaskwarriorColumns" } })
    table.sort(tasks, by_due)
    for _, t in ipairs(tasks) do
      push(task_segs(t, now))
      state.line_tasks[#lines] = t
    end
  end

  if #overdue > 0 then
    section("지난 마감", overdue, "TaskwarriorOverdue")
  end
  local d = os.date("*t", now)
  for i = 0, config.options.agenda.days - 1 do
    local ts = os.time({ year = d.year, month = d.month, day = d.day + i, hour = 12 })
    local key = os.date("%Y-%m-%d", ts)
    local wd = tonumber(os.date("%w", ts))
    local label = os.date("%m/%d", ts) .. " (" .. weekday_names[wd + 1] .. ")"
    if i == 0 then
      label = label .. " 오늘"
    elseif i == 1 then
      label = label .. " 내일"
    end
    local tasks = buckets[key]
    if tasks then
      section(label, tasks, i == 0 and "TaskwarriorDueSoon" or "TaskwarriorHeader")
    else
      push({ { " " .. label .. "  —", (wd == 0 or wd == 6) and "TaskwarriorWeekend" or "TaskwarriorColumns" } })
    end
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

  local agenda = state.view == "agenda"
  push({
    { " " .. (agenda and "Agenda · " or "") .. (state.filter == "" and "(no filter)" or state.filter), "TaskwarriorHeader" },
    { string.format("  [%d]", #state.tasks), "TaskwarriorColumns" },
  })
  push({
    { " " .. pad("ID", 4) .. pad("P", 1) .. pad("Due", 6) .. pad("Project", 13) .. "Description", "TaskwarriorColumns" },
  })

  state.line_tasks = {}
  local now = os.time()
  if agenda then
    render_agenda(lines, hls, push, now)
  else
    for _, t in ipairs(state.tasks) do
      push(task_segs(t, now))
      state.line_tasks[#lines] = t
    end
    if #state.tasks == 0 then
      push({ { "  (표시할 태스크 없음 — 'a' 로 추가)", "TaskwarriorColumns" } })
    end
  end

  local shown = vim.tbl_count(state.line_tasks)
  if shown ~= #state.tasks then
    lines[1] = lines[1] .. string.format("  (표시 %d)", shown)
  end
  util.set_lines(state.buf, ns, lines, hls)
end

function M.refresh()
  local cursor = (state.win and api.nvim_win_is_valid(state.win)) and api.nvim_win_get_cursor(state.win) or nil
  local filter = state.filter
  if state.view == "agenda" then
    filter = filter == "" and "due.any:" or ("( " .. filter .. " ) due.any:")
  end
  local tasks, err = cli.export(filter)
  if not tasks then
    vim.notify("taskwarrior: " .. vim.trim(err or "export 실패"), vim.log.levels.ERROR)
    tasks = {}
  end
  state.tasks = tasks
  render()
  if cursor and state.win and api.nvim_win_is_valid(state.win) then
    local last = api.nvim_buf_line_count(state.buf)
    api.nvim_win_set_cursor(state.win, { math.min(cursor[1], last), cursor[2] })
  end
end

local function current_task()
  if not (state.win and api.nvim_win_is_valid(state.win)) then
    return nil
  end
  local lnum = api.nvim_win_get_cursor(state.win)[1]
  local t = state.line_tasks[lnum]
  if not t then
    vim.notify("taskwarrior: 커서 위치에 태스크가 없습니다", vim.log.levels.WARN)
  end
  return t
end

local function run_and_refresh(args, ok_msg)
  local ok, out = cli.run(args)
  if not ok then
    vim.notify("taskwarrior: " .. vim.trim(out), vim.log.levels.ERROR)
  elseif ok_msg then
    vim.notify("taskwarrior: " .. ok_msg, vim.log.levels.INFO)
  end
  M.refresh()
end

local function split_words(s)
  local words = {}
  for w in s:gmatch("%S+") do
    words[#words + 1] = w
  end
  return words
end

local function open_info_float(title, lines)
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = math.min(width + 2, math.floor(vim.o.columns * 0.9))
  local height = math.min(math.max(#lines, 1), math.floor(vim.o.lines * 0.8))

  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = config.options.window.border,
    title = title,
    title_pos = "center",
  })
  for _, key in ipairs({ "q", "<Esc>", "<CR>" }) do
    vim.keymap.set("n", key, function()
      if api.nvim_win_is_valid(win) then
        api.nvim_win_close(win, true)
      end
    end, { buffer = buf, nowait = true, silent = true })
  end
end

function M.show_detail(t)
  local ok, out = cli.run({ t.uuid, "information" })
  if not ok then
    vim.notify("taskwarrior: " .. vim.trim(out), vim.log.levels.ERROR)
    return
  end
  local lines = vim.split(out, "\n", { trimempty = true })
  open_info_float(string.format(" Task %s ", (t.id and t.id ~= 0) and t.id or t.uuid:sub(1, 8)), lines)
end

function M.show_help()
  local km = config.options.keymaps
  local items = {
    { km.add, "태스크 추가 (task add ...)" },
    { km.done, "완료 처리" },
    { km.delete, "삭제" },
    { km.modify, "수정 (task modify ...)" },
    { km.toggle_start, "start/stop 토글" },
    { km.priority, "우선순위 설정" },
    { km.annotate, "주석(annotation) 추가" },
    { km.undo, "되돌리기 (task undo)" },
    { km.filter, "필터 변경" },
    { km.refresh, "새로고침" },
    { km.detail, "상세 정보" },
    { km.agenda, "목록 ↔ 주간 일정(agenda) 전환" },
    { km.calendar, "달력 열기" },
    { km.tui, "taskwarrior-tui 열기" },
    { km.help, "도움말" },
    { km.quit, "닫기" },
  }
  local lines = {}
  for _, item in ipairs(items) do
    lines[#lines + 1] = string.format("  %-6s %s", item[1], item[2])
  end
  open_info_float(" Keymaps ", lines)
end

local function set_keymaps(buf)
  local km = config.options.keymaps
  local function map(key, fn, desc)
    if key and key ~= "" then
      vim.keymap.set("n", key, fn, { buffer = buf, nowait = true, silent = true, desc = "Taskwarrior: " .. desc })
    end
  end

  map(km.quit, M.close, "close")
  map("<Esc>", M.close, "close")
  map(km.refresh, M.refresh, "refresh")
  map(km.help, M.show_help, "help")

  map(km.add, function()
    vim.ui.input({ prompt = "task add > " }, function(input)
      if not input or vim.trim(input) == "" then
        return
      end
      run_and_refresh(vim.list_extend({ "add" }, split_words(input)), "추가됨")
    end)
  end, "add")

  map(km.done, function()
    local t = current_task()
    if not t then
      return
    end
    if config.options.confirm.done and vim.fn.confirm("완료 처리: " .. t.description .. " ?", "&Yes\n&No") ~= 1 then
      return
    end
    run_and_refresh({ t.uuid, "done" }, "완료 처리됨")
  end, "done")

  map(km.delete, function()
    local t = current_task()
    if not t then
      return
    end
    if config.options.confirm.delete and vim.fn.confirm("삭제: " .. t.description .. " ?", "&Yes\n&No") ~= 1 then
      return
    end
    run_and_refresh({ t.uuid, "delete" }, "삭제됨")
  end, "delete")

  map(km.modify, function()
    local t = current_task()
    if not t then
      return
    end
    vim.ui.input({ prompt = "task modify > " }, function(input)
      if not input or vim.trim(input) == "" then
        return
      end
      run_and_refresh(vim.list_extend({ t.uuid, "modify" }, split_words(input)), "수정됨")
    end)
  end, "modify")

  map(km.toggle_start, function()
    local t = current_task()
    if not t then
      return
    end
    run_and_refresh({ t.uuid, t.start and "stop" or "start" })
  end, "start/stop")

  map(km.priority, function()
    local t = current_task()
    if not t then
      return
    end
    vim.ui.select({ "H", "M", "L", "(없음)" }, { prompt = "우선순위" }, function(choice)
      if not choice then
        return
      end
      run_and_refresh({ t.uuid, "modify", "priority:" .. (choice == "(없음)" and "" or choice) })
    end)
  end, "priority")

  map(km.annotate, function()
    local t = current_task()
    if not t then
      return
    end
    vim.ui.input({ prompt = "annotate > " }, function(input)
      if not input or vim.trim(input) == "" then
        return
      end
      run_and_refresh({ t.uuid, "annotate", input }, "주석 추가됨")
    end)
  end, "annotate")

  map(km.undo, function()
    run_and_refresh({ "undo" }, "undo 실행됨")
  end, "undo")

  map(km.filter, function()
    vim.ui.input({ prompt = "filter > ", default = state.filter }, function(input)
      if input == nil then
        return
      end
      state.filter = vim.trim(input)
      M.refresh()
    end)
  end, "filter")

  map(km.detail, function()
    local t = current_task()
    if not t then
      return
    end
    M.show_detail(t)
  end, "detail")

  map(km.agenda, function()
    state.view = state.view == "agenda" and "list" or "agenda"
    M.refresh()
  end, "toggle agenda")

  map(km.calendar, function()
    M.close()
    require("taskwarrior.calendar").open()
  end, "calendar")

  map(km.tui, function()
    M.close()
    require("taskwarrior.tui").open()
  end, "taskwarrior-tui")
end

---@param opts table|nil { view = "list"|"agenda", filter = string } 생략 시 기본 목록/필터
function M.open(opts)
  opts = opts or {}
  state.view = opts.view or "list"
  state.filter = opts.filter or config.options.filter
  if state.win and api.nvim_win_is_valid(state.win) then
    api.nvim_set_current_win(state.win)
    M.refresh()
    return
  end

  if vim.fn.executable(config.options.task_bin) ~= 1 then
    vim.notify("taskwarrior: '" .. config.options.task_bin .. "' 실행 파일을 찾을 수 없습니다", vim.log.levels.ERROR)
    return
  end

  M.ensure_hl()
  local opts = config.options

  state.buf = api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].filetype = "taskwarrior"

  local width = math.floor(vim.o.columns * opts.window.width)
  local height = math.floor(vim.o.lines * opts.window.height)
  state.win = api.nvim_open_win(state.buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = opts.window.border,
    title = opts.window.title,
    title_pos = "center",
  })
  vim.wo[state.win].cursorline = true
  vim.wo[state.win].wrap = false

  set_keymaps(state.buf)

  api.nvim_create_autocmd("BufWipeout", {
    buffer = state.buf,
    callback = function()
      state.buf, state.win = nil, nil
    end,
  })

  M.refresh()
  if api.nvim_buf_line_count(state.buf) >= 3 then
    api.nvim_win_set_cursor(state.win, { 3, 0 })
  end
end

function M.close()
  if state.win and api.nvim_win_is_valid(state.win) then
    api.nvim_win_close(state.win, true)
  end
  state.buf, state.win = nil, nil
end

function M.toggle()
  if state.win and api.nvim_win_is_valid(state.win) then
    M.close()
  else
    M.open()
  end
end

return M
