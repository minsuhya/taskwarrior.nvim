# taskwarrior.nvim

[Taskwarrior](https://taskwarrior.org/) 를 Neovim 안에서 lazygit 스타일의 플로팅 윈도우로 관리하는 플러그인입니다.

- `task export` 기반의 네이티브 Lua UI — 목록 조회, 추가, 완료, 삭제, 수정, start/stop, 우선순위, 주석, undo, 필터
- urgency 내림차순 정렬, 기한(overdue/임박) 색상 표시, 진행 중(started) 태스크 강조
- `vim.ui.input` / `vim.ui.select` 사용 — AstroNvim의 snacks/telescope UI와 자연스럽게 통합
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
  cmd = { "TaskWarrior", "TaskWarriorTui" },
  keys = {
    { "<Leader>lt", "<Cmd>TaskWarrior<CR>", desc = "Taskwarrior" },
  },
  opts = {},
}
```

### AstroNvim (v4/v5)

`lua/plugins/taskwarrior.lua`:

```lua
return {
  "minsuhya/taskwarrior.nvim",
  cmd = { "TaskWarrior", "TaskWarriorTui" },
  opts = {},
  specs = {
    {
      "AstroNvim/astrocore",
      opts = {
        mappings = {
          n = {
            ["<Leader>lt"] = { "<Cmd>TaskWarrior<CR>", desc = "Taskwarrior" },
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
| `t`     | taskwarrior-tui 플로팅 터미널 열기        |
| `?`     | 도움말                                    |
| `q`/`<Esc>` | 닫기                                  |

추가/수정 입력은 task CLI 문법을 그대로 사용합니다:

```
task add > 보고서 작성 project:work +urgent due:friday priority:H
task modify > due:tomorrow project:home
filter > project:work status:pending
```

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
