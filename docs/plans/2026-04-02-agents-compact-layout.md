# Agents Compact Layout Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在固定大小的 Notch 展开窗口内，提高 Agents 页面信息密度，去除大卡片浪费空间，同时保留关键交互（Jump、Approve/Deny、问答回复）。

**Architecture:** 保持现有数据流（`AgentHubManager` -> `AgentsTabView` -> `AgentSessionCardView`）不变，仅重构展示层。将顶部摘要改为单行紧凑统计条；将会话由大卡片改为“行头+按需展开详情”的列表项；保留 pending action 的优先展示与处理按钮。

**Tech Stack:** SwiftUI, Defaults, 现有 Agent models/localization。

### Task 1: 压缩顶部摘要与筛选区

**Files:**
- Modify: `boringNotch/components/Agents/AgentsTabView.swift`
- Modify: `boringNotch/components/Agents/AgentClosedSummaryView.swift`

**Step 1: 写 failing 视觉预期（注释约束）**
- 在代码注释中明确“summary 单行、减少 tile”。

**Step 2: 实现紧凑摘要条**
- 把 `AgentClosedSummaryView` 改为单行指标（运行数、待处理、刷新时间、tokens/cost）
- 去掉 `LazyVGrid stat tiles`，避免占高度。

**Step 3: 统一筛选栏密度**
- 在 `AgentsTabView` 减少纵向 spacing/padding。
- 将筛选条保持单行，减少按钮内边距。

**Step 4: 运行构建验证**
- Run: `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build`
- Expected: BUILD SUCCEEDED

### Task 2: 会话卡片改为紧凑行式布局

**Files:**
- Modify: `boringNotch/components/Agents/AgentSessionCardView.swift`
- Modify: `boringNotch/components/Agents/AgentsTabView.swift`

**Step 1: 行头重排**
- 第一行：provider/state/title（单行截断）+ elapsed/usage + Jump。
- 去除大图形 provider glyph 与过大 padding。

**Step 2: 详情按需展示**
- 增加 `isExpanded`；默认仅在存在 pending action 时展开，其余折叠。
- `detailText` 放到折叠区域，限制行数。

**Step 3: Pending action 紧凑化**
- 保留 approve/deny 与问题回复，但改成更紧凑控件（更小间距和内边距）。

**Step 4: 列表密度调优**
- `LazyVStack` item spacing 降低。
- 空状态和 banner 统一小间距。

### Task 3: 文案与可用性守护

**Files:**
- Modify: `boringNotch/Localizable.xcstrings`（若新增 key）

**Step 1: 补齐新增 key**
- 若新增“展开/收起”等文案，补 `en` + `zh-Hans`。

**Step 2: 验证无 missing key**
- 运行 key 扫描脚本或 `rg` 对照。

### Task 4: 本地运行与交付

**Files:**
- None

**Step 1: 启动应用**
- 打开最新 Debug 构建产物。

**Step 2: 人工检查**
- 在固定 notch 展开尺寸下验证：
  - 首屏可见更多 session 行
  - pending action 可直接操作
  - 详情不再默认撑高页面

