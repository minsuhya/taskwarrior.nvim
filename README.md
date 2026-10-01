# taskwarrior.nvim

[Taskwarrior](https://taskwarrior.org/) 를 Neovim 안에서 lazygit 스타일의 플로팅 윈도우로 관리하는 플러그인입니다.

- `task export` 기반의 네이티브 Lua UI — 목록 조회, 추가, 완료, 삭제, 수정, start/stop, 우선순위, 주석, undo, 필터
- urgency 내림차순 정렬, 기한(overdue/임박) 색상 표시, 진행 중(started) 태스크 강조
- `vim.ui.input` / `vim.ui.select` 사용 — AstroNvim의 snacks/telescope UI와 자연스럽게 통합
- 월 달력(`:TaskWarriorCalendar`)과 주간 일정 agenda(`:TaskWarriorAgenda`) — 날짜별 due 태스크 확인·추가
- 보너스: `taskwarrior-tui` 가 설치되어 있으면 플로팅 터미널로 바로 열기 (`t` 키 또는 `:TaskWarriorTui`)

## 요구 사항

- Neovim >= 0.9
- [taskwarrior](https://taskwarrior.org/) (`task` 명령) — `brew install task`
- (선택) [taskwarrior-tui](https://github.com/kdheepak/taskwarrior-tui) — `brew install taskwarrior-tui`

## 설치

### lazy.nvim

```lua
{
  "minsuhya/taskwarrior.nvim",
  cmd = { "TaskWarrior", "TaskWarriorAgenda", "TaskWarriorCalendar", "TaskWarriorCalendarRaw", "TaskWarriorTui" },
  keys = {
    { "<Leader>lt", "<Cmd>TaskWarrior<CR>", desc = "Taskwarrior" },
    { "<Leader>la", "<Cmd>TaskWarriorAgenda<CR>", desc = "Taskwarrior agenda" },
    { "<Leader>lc", "<Cmd>TaskWarriorCalendar<CR>", desc = "Taskwarrior calendar" },
  },
  opts = {},
}
```

### AstroNvim (v4/v5)

`lua/plugins/taskwarrior.lua`:

```lua
return {
  "minsuhya/taskwarrior.nvim",
  cmd = { "TaskWarrior", "TaskWarriorAgenda", "TaskWarriorCalendar", "TaskWarriorCalendarRaw", "TaskWarriorTui" },
  opts = {},
  specs = {
    {
      "AstroNvim/astrocore",
      opts = {
        mappings = {
          n = {
            ["<Leader>lt"] = { "<Cmd>TaskWarrior<CR>", desc = "Taskwarrior" },
            ["<Leader>la"] = { "<Cmd>TaskWarriorAgenda<CR>", desc = "Taskwarrior agenda" },
            ["<Leader>lc"] = { "<Cmd>TaskWarriorCalendar<CR>", desc = "Taskwarrior calendar" },
          },
        },
      },
    },
  },
}
```

## 사용법

`<Leader>lt` 또는 `:TaskWarrior` 로 창을 토글합니다.

| 키      | 동작                                      |
| ------- | ----------------------------------------- |
| `a`     | 태스크 추가 (`task add ...` 문법 그대로)  |
| `d`     | 완료 처리                                 |
| `x`     | 삭제 (확인 후)                            |
| `m`     | 수정 (`task modify ...` 문법 그대로)      |
| `s`     | start/stop 토글                           |
| `p`     | 우선순위 설정 (H/M/L/없음)                |
| `A`     | 주석(annotation) 추가                     |
| `u`     | 되돌리기 (`task undo`)                    |
| `f`     | 필터 변경 (task 필터 문법)                |
| `r`     | 새로고침                                  |
| `<CR>`  | 상세 정보 (`task information`)            |
| `v`     | 목록 ↔ 주간 일정(agenda) 전환             |
| `c`     | 달력 열기                                 |
| `t`     | taskwarrior-tui 플로팅 터미널 열기        |
| `?`     | 도움말                                    |
| `q`/`<Esc>` | 닫기                                  |

추가/수정 입력은 task CLI 문법을 그대로 사용합니다:

```
task add > 보고서 작성 project:work +urgent due:friday priority:H
task modify > due:tomorrow project:home
filter > project:work status:pending
```

### 주간 일정 (agenda)

`:TaskWarriorAgenda` 또는 목록에서 `v`. 현재 필터에 해당하는 태스크 중 due 가 있는 것만
**지난 마감** 섹션과 오늘부터 `agenda.days` 일(기본 14일) 동안의 날짜별 섹션으로 묶어 보여줍니다.
태스크 줄 위에서는 완료·수정·start 등 목록 화면의 키가 그대로 동작합니다.

```
 지난 마감  (2)
 161  H -21d   project-a     원서 접수
 10/01 (목) 오늘  (1)
 133    today  personal      카드 충전
 10/02 (금) 내일  (2)
 ...
 10/03 (토)  —
```

### 달력

`:TaskWarriorCalendar` 또는 목록에서 `c`. 날짜 옆 위첨자 숫자는 그날 마감인 pending 태스크 수이고,
아래에는 선택한 날짜의 태스크 목록이 표시됩니다. 주 시작 요일은 taskrc 의 `weekstart` 를 따릅니다.

```
             2026년 10월
    일   월   화   수   목   금   토
                       1³   2²   3¹
   4¹   5⁴   6²   7³   8    9   10¹
```

| 키            | 동작                                              |
| ------------- | ------------------------------------------------- |
| `h`/`l`       | 하루 이동                                         |
| `j`/`k`       | 일주일 이동                                       |
| `[`/`]` (`H`/`L`) | 이전/다음 달                                  |
| `.`           | 오늘로 이동                                       |
| `<CR>`        | 선택 날짜의 태스크를 목록 화면에서 열기           |
| `a`           | 선택 날짜를 due 로 태스크 추가                    |
| `v`           | 주간 일정 열기                                    |
| `r` / `?` / `q` | 새로고침 / 도움말 / 닫기                        |

`:TaskWarriorCalendarRaw` 는 `task calendar` 의 원래 출력(3개월, taskwarrior 색상 그대로)을
플로팅 터미널로 보여줍니다 (`q` 로 닫기).

## 설정 (기본값)

```lua
require("taskwarrior").setup({
  task_bin = "task",
  tui_bin = "taskwarrior-tui",
  filter = "status:pending",   -- 기본 필터
  window = {
    width = 0.85,              -- editor 대비 비율
    height = 0.8,
    border = "rounded",
    title = " Taskwarrior ",
  },
  agenda = {
    days = 14,                 -- 오늘부터 표시할 일수
  },
  calendar = {
    weekstart = nil,           -- "sunday" | "monday", nil 이면 taskrc 의 weekstart
  },
  confirm = {
    done = false,              -- 완료 처리 시 확인 여부
    delete = true,             -- 삭제 시 확인 여부
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
    agenda = "v",
    calendar = "c",
    tui = "t",
    help = "?",
    quit = "q",
  },
})
```

## 팁: solarized 테마에서 태스크가 안 보일 때

taskwarrior 기본 `solarized-dark-256.theme` 은 blocked/blocking 태스크를
`color0 on color10` 처럼 팔레트 상대색으로 칠하기 때문에, 터미널 팔레트에
따라 어두운 글자가 어두운 배경 위에 얹혀 태스크가 보이지 않을 수 있습니다
(플로팅 터미널로 여는 taskwarrior-tui 포함).

`~/.taskrc` 에서 테마 include **뒤에** 절대 256색 오버라이드를 추가하면
solarized 팔레트를 유지하면서 가시성이 해결됩니다:

```
include solarized-dark-256.theme

# Solarized visibility overrides (must come after the theme include)
color.blocked=color136
color.blocking=bold color166
color.due=color166
color.due.today=bold color160
color.overdue=bold color125
color.alternate=on color235
```

## License

MIT
