local config = require("taskwarrior.config")

local M = {}

---@param args string[] task 명령 인자
---@return boolean ok, string output
function M.run(args)
  local cmd = { config.options.task_bin, "rc.confirmation=off", "rc.verbose=nothing" }
  vim.list_extend(cmd, args)
  local out = vim.fn.system(cmd)
  return vim.v.shell_error == 0, out
end

---필터 문자열로 task export 후 urgency 내림차순 정렬된 테이블 반환
---@param filter string|nil
---@return table|nil tasks, string|nil err
function M.export(filter)
  local args = {}
  if filter and filter ~= "" then
    for word in filter:gmatch("%S+") do
      table.insert(args, word)
    end
  end
  table.insert(args, "export")

  local ok, out = M.run(args)
  if not ok then
    return nil, out
  end

  local decoded_ok, tasks = pcall(vim.json.decode, out)
  if not decoded_ok or type(tasks) ~= "table" then
    return nil, "task export 결과(JSON) 파싱 실패"
  end

  table.sort(tasks, function(a, b)
    return (a.urgency or 0) > (b.urgency or 0)
  end)
  return tasks
end

return M
