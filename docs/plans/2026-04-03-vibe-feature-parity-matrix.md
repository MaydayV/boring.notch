# Vibe Feature Parity Matrix

## Scope

对标目标：`Claude/Codex/Gemini/Cursor/OpenCode/Droid` 六类 Agent 的监控、交互、跳转、计划预览和提醒体验。

## Matrix

| Feature | Target Behavior | Current Module(s) | Status | Acceptance |
| --- | --- | --- | --- | --- |
| Provider coverage | 6 provider 一等实体可展示/筛选/统计 | `AgentModels`, `AgentsTabView`, `AgentsSettingsView` | Done | 六类 provider 均可独立显示 |
| Real-time status | running/waiting approval/waiting question/done 正确收敛 | `AgentHubManager`, `AgentBridgeClient`, `AgentProviderScanner` | In Progress | 状态不被扫描错误回抬 |
| GUI approvals | 面板内 approve/deny/always/bypass | `AgentsTabView`, `AgentSessionCardView`, bridge response path | Done | 已支持 approve/deny，且支持 option-driven `always/bypass` |
| AskUserQuestion | 选项 + 文本回答 | `AgentSessionCardView`, `AgentHubManager` | Partial | 问题响应闭环可重复验证 |
| Terminal jump precision | 命中 window/tab/pane，并回退稳健 | `AgentJumpService` | In Progress | iTerm/Terminal 稳定；其他终端有明确回退 |
| Plan preview | Markdown 计划片段可读、可交互 | `AgentSessionCardView` | Partial | 标题/列表/代码块渲染正确 |
| Pixel island animation | 闭合态像素动效 + pending 强提示 | `ContentView` | Partial | 已完成 scan reveal + pending burst + warning ribbon，待实机节奏验收 |
| Hook auto setup | Install/Repair 幂等，状态可见 | `AgentHookInstaller`, `AgentsSettingsView` | Partial | 重复安装不破坏配置 |
| Multi-terminal compatibility | iTerm/Ghostty/Warp/Terminal/VS Code/Cursor | jump + hooks + bridge | Planned | 至少 4 类终端稳定可用 |
| Diagnostics | 导出可排查 hook/status/sessions | `AgentHookInstaller`, `AgentHubManager`, settings | Done | 支持 Copy diagnostics 与 Export JSON，可复盘 hook/session/action 状态 |

## Iteration Exit Criteria

1. 每轮至少提升 2 个 `In Progress/Planned` 项到 `Partial/Done`。
2. 不允许出现“编译通过但交互回归”未记录情况。
3. 所有行为变化需在 PR/提交说明中给出对应矩阵项。
