# Agent V2 Acceptance Checklist

## 1. 统计口径

1. 同时有 Claude 与 Codex 会话时，闭合态显示的 Provider 与数量一致（不可跨 provider 混算）。
2. 仅有单 provider 会话时，数量与该 provider 实际活跃/待处理一致。
3. 切换 provider 过滤后，展开面板统计与闭合态统计一致。

## 2. 会话识别与状态

1. 新会话开始后 1~2 秒内出现。
2. 动作请求（approve/question）出现后状态切为 waiting。
3. 动作响应后状态回收，不残留幽灵 pending。
4. 历史会话不会长期误判为 running（超过活跃窗口应降级）。

## 3. 子代理

1. 存在 `subagentParentThreadId` 时挂靠到父会话。
2. 子代理行数变化可触发对应卡片/行高度自适应。

## 4. 交互动作

1. `Approve` 生效并回写响应。
2. `Deny` 生效并回写响应。
3. `Answer` 生效并回写响应。
4. `Jump` 可打开终端并执行 resume 命令。
5. AskUserQuestion 支持选项和自由文本两种回复路径。

## 5. 稳定性

1. 点击 Agents tab 不会卡死。
2. 授权目录后不会导致 UI 长时间阻塞。
3. 切换布局模式（简洁/详细）不会造成列表重建卡顿。

## 6. 多语言

1. 中文环境设置页、菜单、Agent 面板无英文残留（专有名词除外）。
2. 英文环境文案完整可读，不显示 key。

## 7. 构建与冒烟

1. Run: `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -sdk macosx build`
2. Expected: `BUILD SUCCEEDED`
3. 打开 Debug 应用并完成上述 1~6 项人工验收。

## 8. 对标特性专项

1. 支持并可识别 6 类 provider：Claude/Codex/Gemini/Cursor/OpenCode/Droid。
2. 至少 iTerm2 与 Terminal.app 达到“窗口 + tab”级跳转。
3. Plan 预览支持 Markdown 渲染（标题、列表、代码块）。
4. 可配置 8-bit 提醒音（会话启动、待审批、提问）。
