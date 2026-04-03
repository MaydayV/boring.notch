# Agents Style Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 参考 Vibe 的设置与展示风格，为 Agents 提供可切换的“简洁/详细”样式，并重排设置页与展开页层级，减少噪音信息。

**Architecture:** 增加统一样式偏好（Defaults Key + Enum），由 `AgentsSettingsView` 负责设置与预览，由 `AgentsTabView/AgentSessionCardView` 根据样式渲染不同密度。保持现有扫描、动作处理逻辑不变，仅重构展示和交互组织。

**Tech Stack:** SwiftUI, Defaults, Localizable.xcstrings.

### Task 1: 样式配置模型与多语言键

**Files:**
- Modify: `boringNotch/enums/generic.swift`
- Modify: `boringNotch/models/Constants.swift`
- Modify: `boringNotch/Localizable.xcstrings`

**Step 1: 新增样式枚举**
- `AgentPanelStyle` with `.compact` / `.detailed`.

**Step 2: 新增 Defaults key**
- `agentPanelStyle`，默认 `compact`.

**Step 3: 添加 i18n key**
- 设置页文案：面板、样式、简洁、详细、预览说明等。

### Task 2: 设置页视觉改版（参考 Vibe 结构）

**Files:**
- Modify: `boringNotch/components/Settings/Views/AgentsSettingsView.swift`

**Step 1: 新增“面板样式”分区**
- 顶部 preview（黑色 notch capsule + 会话数量）
- 下方双选项卡片（简洁 / 详细）

**Step 2: 保留关键开关，减少冗余噪音**
- General + Providers + CLI Hooks 保留
- 将层级更清晰，弱化长段说明文案在首屏的占比

**Step 3: 样式绑定**
- 选择卡片写入 `agentPanelStyle`

### Task 3: Agents 面板样式联动

**Files:**
- Modify: `boringNotch/components/Agents/AgentsTabView.swift`
- Modify: `boringNotch/components/Agents/AgentSessionCardView.swift`
- Modify: `boringNotch/components/Agents/AgentClosedSummaryView.swift`

**Step 1: 样式注入**
- 读取 `@Default(.agentPanelStyle)`

**Step 2: 简洁模式**
- 高密度行式布局，默认折叠详情，仅动作会话展开

**Step 3: 详细模式**
- 更明显的标题与状态层级，详情默认展开，pending action 区域更突出

### Task 4: 验证与运行

**Files:**
- None

**Step 1: Build**
- `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug build`

**Step 2: Launch**
- 启动 Debug 应用进行人工复测

