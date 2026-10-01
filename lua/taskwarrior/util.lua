local config = require("taskwarrior.config")

local M = {}

-- 1970-01-01 기준 일수 (proleptic Gregorian, Howard Hinnant 의 days_from_civil)
local function days_from_civil(y, m, d)
  y = m <= 2 and y - 1 or y
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end

-- "20260723T150000Z" (UTC) -> epoch (로컬 타임존/DST 와 무관하게 계산)
function M.parse_ts(s)
  local y, mo, d, h, mi, se = s:match("^(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)Z$")
  if not y then
    return nil
  end
  local days = days_from_civil(tonumber(y), tonumber(mo), tonumber(d))
  return days * 86400 + tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(se)
end

---task 의 due 를 로컬 날짜 키("YYYY-MM-DD")로 변환
function M.due_key(t)
  local ts = t.due and M.parse_ts(t.due)
  return ts and os.date("%Y-%m-%d", ts) or nil
end

-- 표시 폭 기준 패딩/자르기 (한글 등 멀티바이트 대응)
function M.pad(s, width)
  s = s or ""
  local dw = vim.fn.strdisplaywidth(s)
  if dw > width then
    s = vim.fn.strcharpart(s, 0, width - 1) .. "…"
    dw = vim.fn.strdisplaywidth(s)
  end
  return s .. string.rep(" ", math.max(0, width - dw + 1))
end

---segs = { { text, hl_group|nil }, ... } 를 한 줄로 합쳐 lines/hls 에 추가
function M.push(lines, hls, segs)
  local line = ""
  for _, seg in ipairs(segs) do
    local text, group = seg[1], seg[2]
    if group and #text > 0 then
      hls[#hls + 1] = { #lines, #line, #line + #text, group }
    end
    line = line .. text
  end
  lines[#lines + 1] = line
end

function M.set_lines(buf, ns, lines, hls)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_set_extmark(buf, ns, h[1], h[2], { end_col = h[3], hl_group = h[4] })
  end
end

---가운데 정렬된 플로팅 창
function M.open_float(buf, width, height, title)
  width = math.min(width, vim.o.columns - 4)
  height = math.min(height, vim.o.lines - 4)
  return vim.api.nvim_open_win(buf, true, {
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
end

return M
