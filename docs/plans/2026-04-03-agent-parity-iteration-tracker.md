# Agent Parity Multi-Round Iteration Tracker

## Goal

基于 `2026-04-02-agent-v2-realignment-plan.md`，按“可并行、可验收、可回退”的方式多轮迭代，持续复刻 Vibe Island 的功能与交互逻辑。

## Execution Rules

1. 每轮先定义修改范围（文件级 ownership）再动代码。
2. 每轮最多 3-4 个并行任务，禁止同文件并行写入。
3. 每轮完成后必须执行一次 `xcodebuild` 编译门禁。
4. 每轮输出差异复盘：已达成 / 未达成 / 下一轮补位。
5. 对标验证优先级：行为一致性 > 状态机正确性 > 视觉细节。

## Round Breakdown

### Round 1 (Completed)

**Target**
- Provider 一等实体化（cursor/droid 等）
- event-first 状态机强化
- 跳转能力增强
- 像素上岛动画第一版

**Ownership**
- Worker A:
  - `boringNotch/managers/Agents/AgentModels.swift`
  - `boringNotch/models/Constants.swift`
  - `boringNotch/components/Settings/Views/AgentsSettingsView.swift`
  - `boringNotch/components/Agents/AgentsTabView.swift`
  - `boringNotch/ContentView.swift`
- Worker B:
  - `boringNotch/managers/Agents/AgentHubManager.swift`
  - `boringNotch/managers/Agents/AgentProviderScanner.swift`
  - `boringNotch/managers/Agents/AgentBridgeClient.swift`
- Worker C:
  - `boringNotch/managers/Agents/AgentJumpService.swift`
- Main:
  - 集成、冲突消解、编译验收

**Acceptance Gate**
- 编译通过
- Agents 面板可看到新增 provider
- action/request 状态不会被扫描结果错误回抬
- 跳转行为不回归 iTerm/Terminal

### Round 2 (Completed)

**Target**
- 高密度行视图（row-based list）
- Plan 预览与 AskUserQuestion 交互细节补齐
- 设置页“先可用后高级”信息架构收敛

**Ownership**
- UI 组件：
  - `boringNotch/components/Agents/AgentSessionRowView.swift` (new)
  - `boringNotch/components/Agents/AgentsTabView.swift`
  - `boringNotch/components/Agents/AgentSessionCardView.swift`
- 设置：
  - `boringNotch/components/Settings/Views/AgentsSettingsView.swift`
  - `boringNotch/Localizable.xcstrings`

**Acceptance Gate**
- 一屏可见更多活跃会话
- pending 操作（Approve/Deny/Answer/Jump）单层可达
- 中英文文案完整

**Result**
- 已完成高密度行视图（`AgentSessionRowView`）并保留 `AgentSessionCardView` 兼容封装。
- 已补齐行内动作闭环（含 planReview 的 approve/deny）。
- 已完成首启三步重构与空态语义更新（等待会话 + 打开设置/修复 hooks）。
- 主线构建门禁通过。

### Round 3 (Completed)

**Target**
- Hook 安装/修复自动化完善
- 诊断包与可观测性提升
- 动效二阶段：closed/open 过渡复刻（scan reveal）

**Ownership**
- Hook & diagnostics:
  - `boringNotch/managers/Agents/AgentHookInstaller.swift`
  - `boringNotch/managers/Agents/AgentBridgeClient.swift`
  - `boringNotch/components/Settings/Views/AgentsSettingsView.swift`
- Animation polish:
  - `boringNotch/ContentView.swift`
  - `boringNotch/components/Agents/AgentCompactNotchView.swift` (new, optional)

**Acceptance Gate**
- Install/Repair 幂等
- diagnostics 输出可用于复盘 hook 与会话状态
- 上岛/收岛动效达到对标节奏与信息层次

**Current Result**
- 已完成上岛动效二/三阶段：`scan reveal + state pulse + pending burst + warning ribbon + open panel pixelated transition`。
- 所有动画改动限定在 `ContentView.swift`，未改动显示优先级业务分支。
- 主线构建门禁通过。
- 已补齐 diagnostics 导出能力：`Copy diagnostics` + `Export JSON`，覆盖 hook/session/pending actions 快照。
- 已补齐 approvals 的 `always/bypass` 选项解析与回传（provider option-driven）。
- 待完成项：多终端对照验收（至少 4 类终端稳定性记录）。

## Regression Checklist (Every Round)

1. `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -sdk macosx build`
2. 验证 closed notch 优先级：系统事件 > 音乐 > agent（按现有设计策略）。
3. 验证 Agents tab 打开无卡顿。
4. 验证 pending action 可操作并状态收敛。
5. 验证 jump 不破坏现有 iTerm2 / Terminal 行为。
