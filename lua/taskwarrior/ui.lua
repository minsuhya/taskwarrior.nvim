local api = vim.api
local cli = require("taskwarrior.cli")
local config = require("taskwarrior.config")

local M = {}

local ns = api.nvim_create_namespace("taskwarrior_nvim")

local state = {
  buf = nil,
  win = nil,
  tasks = {},
  line_tasks = {}, -- 화면 line 번호 -> task
  filter = nil,
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
}

local function ensure_hl()
  for group, link in pairs(hl_links) do
    api.nvim_set_hl(0, group, { link = link, default = true })
  end
end

-- "20260723T150000Z" (UTC) -> epoch
local function parse_ts(s)
  local y, mo, d, h, mi, se = s:match("^(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)Z$")
  if not y then
    return nil
  end
  local now = os.time()
  local utc_offset = os.difftime(now, os.time(os.date("!*t", now)))
  return os.time({
    year = tonumber(y),
    month = tonumber(mo),
    day = tonumber(d),
    hour = tonumber(h),
    min = tonumber(mi),
    sec = tonumber(se),
  }) + utc_offset
end

local function fmt_due(ts, now)
  local diff = ts - now
  if diff < 0 then
    if -diff < 86400 then
      return "today", "TaskwarriorOverdue"
    end
    return "-" .. math.floor(-diff / 86400) .. "d", "TaskwarriorOverdue"
  end
  local days = math.floor(diff / 86400)
  if days == 0 then
    return "today", "TaskwarriorDueSoon"
  elseif days <= 3 then
    return days .. "d", "TaskwarriorDueSoon"
  end
  return days .. "d", "TaskwarriorDue"
end

-- 표시 폭 기준 패딩/자르기 (한글 등 멀티바이트 대응)
local function pad(s, width)
  s = s or ""
  local dw = vim.fn.strdisplaywidth(s)
  if dw > width then
    s = vim.fn.strcharpart(s, 0, width - 1) .. "…"
    dw = vim.fn.strdisplaywidth(s)
  end
  return s .. string.rep(" ", math.max(0, width - dw + 1))
end

local function render()
  if not (state.buf and api.nvim_buf_is_valid(state.buf)) then
    return
  end

  local lines, hls = {}, {}
  -- segs = { { text, hl_group|nil }, ... } 를 한 줄로 합치고 하이라이트 오프셋 기록
  local function push(segs)
    local line = ""
    local offsets = {}
    for _, seg in ipairs(segs) do
      local text, group = seg[1], seg[2]
      if group and #text > 0 then
        offsets[#offsets + 1] = { #line, #line + #text, group }
      end
      line = line .. text
    end
    lines[#lines + 1] = line
    for _, o in ipairs(offsets) do
      hls[#hls + 1] = { #lines - 1, o[1], o[2], o[3] }
    end
  end

  push({
    { " " .. (state.filter == "" and "(no filter)" or state.filter), "TaskwarriorHeader" },
    { string.format("  [%d]", #state.tasks), "TaskwarriorColumns" },
  })
  push({
    { " " .. pad("ID", 4) .. pad("P", 1) .. pad("Due", 6) .. pad("Project", 13) .. "Description", "TaskwarriorColumns" },
  })

  state.line_tasks = {}
  local now = os.time()
  for _, t in ipairs(state.tasks) do
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
    push(segs)
    state.line_tasks[#lines] = t
  end

  if #state.tasks == 0 then
    push({ { "  (표시할 태스크 없음 — 'a' 로 추가)", "TaskwarriorColumns" } })
  end

  vim.bo[state.buf].modifiable = true
  api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    api.nvim_buf_set_extmark(state.buf, ns, h[1], h[2], { end_col = h[3], hl_group = h[4] })
  end
end

function M.refresh()
  local cursor = (state.win and api.nvim_win_is_valid(state.win)) and api.nvim_win_get_cursor(state.win) or nil
  local tasks, err = cli.export(state.filter)
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

  map(km.tui, function()
    M.close()
    require("taskwarrior.tui").open()
  end, "taskwarrior-tui")
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

  ensure_hl()
  local opts = config.options
  state.filter = state.filter or opts.filter

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
