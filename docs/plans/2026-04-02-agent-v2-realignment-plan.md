# Agent Terminal Tab V2 Realignment Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 对齐 VibeIsland 的 Agent 终端体验，修复 Claude/Codex 统计口径与会话识别偏差，并把固定高度面板重构为高密度、可操作、可扩展的多 Provider 终端中心。

**Architecture:** 采用 `event-first + scan-fallback` 双通道：以 bridge 事件作为唯一实时真相源，文件扫描仅用于冷启动补全。UI 拆成 3 层：闭合态 Notch（摘要）、展开态 Terminal Tab（列表与操作）、设置与首启（安装/权限/样式）。状态机分离 `活跃会话`、`待处理动作`、`子代理` 三类实体，统一由 `AgentHubManager` 聚合。

**Tech Stack:** SwiftUI, AppKit(NSOpenPanel), Defaults, Localizable.xcstrings, 现有 Agents 管理模块 (`AgentBridgeClient`, `AgentHubManager`, `AgentProviderScanner`, `AgentHookInstaller`)。

## 对标应用二次分析结论（本次）

### 证据摘录

1. 参考应用含独立 bridge helper：`Contents/Helpers/vibe-island-bridge`，并明确 `events.ndjson / responses.ndjson` 双文件交互。
2. 二进制可见 Hook 事件字段：`hook_event_name`, `codex_event_type`, `codex_session_start_source`, `codex_transcript_path`。
3. 二进制可见 subagent 结构字段：`subagentId`, `subagentParentThreadId`, `subagentNickname`, `subagentRole`, `subagentType`。
4. 本地化键显示其布局策略是可切换模式：`layout.compact`, `layout.detailed`, `settings.showAgentDetail`。
5. 设置侧存在 `smart suppression`、`autoDetectProbes`、`Jump to Terminal`、`CLI Hooks` 等完整操作链路。

### 对标能力基线（按你提供的帖子要点固化）

1. Provider 覆盖：至少支持 `Claude Code / Codex CLI / Gemini CLI / Cursor Agent / OpenCode / Droid`。
2. 实时状态：明确区分 `running / waiting approval / waiting question / done`。
3. GUI 审批：在面板内完成 `Approve / Deny`，不强制切终端。
4. AskUserQuestion 回答：支持选项回答与自由文本回答。
5. 精确终端跳转：目标为“定位到具体终端窗口 + tab + split pane”。
6. Plan 预览：支持 Markdown 渲染的计划片段预览。
7. 声音反馈：可配置 8-bit 风格提醒（会话启动、待审批、提问）。
8. 零配置优先：首次启用时自动检测并安装 hooks，失败时提供 Repair。
9. 多终端兼容：逐步扩展 iTerm2 / Ghostty / Warp / Terminal.app / VS Code / Cursor 等。

### 当前实现偏差（根因）

1. 统计口径错误：闭合态摘要此前按“全 provider 总数”显示在“单 provider 标签”下，造成 Claude/Codex 数量错配。
2. 会话活跃误判：扫描结果会把历史/弱结构记录提升为 running，缺少“活跃窗口 + 事件心跳”约束。
3. Provider 身份混叠：alias 映射把 Cursor 等映射到 Codex 展示组，导致用户认知上的“Codex 数量异常”。
4. UI 信息密度不足：当前卡片化布局在固定面板高度下浪费垂直空间，关键信息（会话标题、状态、动作）显示效率低。
5. 设置信息架构不一致：当前把过多扫描路径与授权细节直接暴露在主视图，违背“先可用、后高级”的对标体验。

---

### Task 1: 修复统计口径与 Provider 一致性（已开始）

**Files:**
- Modify: `boringNotch/ContentView.swift`
- Modify: `boringNotch/managers/Agents/AgentHubManager.swift`
- Modify: `boringNotch/managers/Agents/AgentModels.swift`

**Step 1: 统一闭合态摘要按 provider 分组计数**
- 将 `compactAgentSnapshot` 的 `activeCount/pendingCount` 改为当前 `preferredProvider` 子集计数。

**Step 2: 明确 Provider 显示分组策略**
- 引入 `canonicalProvider` 与 `sourceProvider` 双字段（展示与统计可配置）。
- 默认展示使用真实来源，不再把 Cursor/Droid/Qoder 无提示并入 Codex/其他组。

**Step 3: 为摘要统计增加回归用例（最小）**
- 覆盖：多 provider 混合、仅单 provider、pending 优先选择 provider。

**Step 4: 编译验证**
- Run: `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -sdk macosx build`
- Expected: `BUILD SUCCEEDED`。

### Task 2: 重建会话活跃状态机（解决“数量错/会话错识别”）

**Files:**
- Modify: `boringNotch/managers/Agents/AgentHubManager.swift`
- Modify: `boringNotch/managers/Agents/AgentProviderScanner.swift`
- Modify: `boringNotch/managers/Agents/AgentBridgeClient.swift`

**Step 1: 增加活跃窗口规则**
- `running` 仅在最近活跃时间窗口内成立（如 90~180 秒，可配置）。
- 超窗后降级为 `idle`，除非存在未解决动作。

**Step 2: 事件优先覆盖扫描状态**
- 如果 bridge 已给出 `session.completed/session.failed/action.*`，扫描层不得回抬到 running。

**Step 3: 请求-响应闭环增强**
- `action.requested` 必须携带 `requestId`；无 `requestId` 时生成稳定键并打告警。
- `action.responded/action.resolved` 统一去重与幂等处理。

**Step 4: 子代理挂靠规则收敛**
- 仅当 `subagentParentThreadId` 命中父会话时挂到父会话；否则进“孤儿子代理缓存”并延迟归并。

### Task 3: Terminal Tab 列表改为高密度“行视图”

**Files:**
- Modify: `boringNotch/components/Agents/AgentsTabView.swift`
- Modify: `boringNotch/components/Agents/AgentSessionCardView.swift`
- Modify: `boringNotch/components/Agents/AgentClosedSummaryView.swift`
- Create: `boringNotch/components/Agents/AgentSessionRowView.swift`

**Step 1: 拆分卡片组件**
- 新增 `AgentSessionRowView`，单行展示：标题、状态、Provider 标签、时间、待处理数。

**Step 2: 子代理自动高度策略**
- 默认行高固定；存在 subagent 时按行数增高（上限可配置），避免一屏被单卡吞掉。

**Step 3: 详情改为按需展开**
- 仅对选中行、待处理动作行或包含错误行展开摘要与操作按钮。

**Step 4: 保持动作优先级**
- `Approve / Deny / Answer / Jump` 固定在行内可达，减少多层点击。

### Task 4: 设置页改版为“先可用后高级”

**Files:**
- Modify: `boringNotch/components/Settings/Views/AgentsSettingsView.swift`
- Modify: `boringNotch/Localizable.xcstrings`

**Step 1: 主区保留 3 件事**
- 布局模式（简洁/详细）
- CLI Hooks 安装修复
- Provider 开关

**Step 2: 高级项折叠**
- 扫描路径、授权目录、原始配置路径放入“高级排查”折叠区，不占首屏。

**Step 3: 目录授权逻辑简化**
- 授权入口统一为“用户目录 + provider 子目录提示”，避免多 provider 重复弹窗。
- 选择目录后立即做轻量可读性探测并给出明确状态。

### Task 5: 闭合态 Notch 信息模型对齐

**Files:**
- Modify: `boringNotch/ContentView.swift`
- Create: `boringNotch/components/Agents/AgentCompactNotchView.swift`

**Step 1: 摘要显示优先级**
- 有待处理动作时显示 `pending` 优先；否则显示活跃会话数。

**Step 2: Provider 与数值一致性**
- 标签 provider 必须与计数 provider 完全一致（同一过滤器）。

**Step 3: 可观测性埋点**
- 输出调试日志：当前摘要 provider、active/pending 计数来源。

### Task 6: 首次启动与空态流程重做

**Files:**
- Modify: `boringNotch/components/Onboarding/OnboardingView.swift`
- Modify: `boringNotch/components/Onboarding/OnboardingFinishView.swift`
- Modify: `boringNotch/boringNotchApp.swift`
- Modify: `boringNotch/Localizable.xcstrings`

**Step 1: 首启关键路径**
- 引导只做三步：识别 CLI → 安装 Hook → 打开终端 tab。

**Step 2: 空态文案与行动按钮**
- 空态显示“等待会话 + 一键打开设置/修复 hooks”。

**Step 3: 对齐多语言**
- 新增文案全部进入 `xcstrings`，禁止硬编码中文/英文。

### Task 7: 验收与回归清单

**Files:**
- Create: `docs/plans/2026-04-02-agent-v2-acceptance-checklist.md`

**Step 1: 功能验收**
- Claude/Codex 独立计数准确。
- 产生待处理请求后 1~2 秒内可见并可操作。
- 选中 provider 时列表与摘要统计一致。

**Step 2: 稳定性验收**
- 打开 Agents tab 不可卡死。
- 切换 provider、切换布局模式、授权目录后无主线程卡顿。

**Step 3: 国际化验收**
- 设置页与菜单无残留英文（在中文环境）。
- 英文环境 key 完整回退正常。

**Step 4: 对标能力验收**
- 至少 6 个 provider 可被识别并正确归类展示。
- Plan 预览卡可显示 Markdown（标题、列表、代码块）。
- Jump 能力至少在 iTerm2 与 Terminal.app 达到“窗口 + tab”级别定位。
- 声音提醒支持独立开关，默认不干扰现有系统音行为。

### Task 8: 像素风上岛动画对标（新增）

**Files:**
- Modify: `boringNotch/ContentView.swift`
- (Optional) Create: `boringNotch/components/Agents/AgentPixelAnimation.swift`
- (Optional) Modify: `boringNotch/models/Constants.swift`
- (Optional) Modify: `boringNotch/components/Settings/Views/AppearanceSettingsView.swift`

**Step 1: 闭合态 Agent Island 像素动画升级**
- 将单一波形条升级为“像素矩阵 + 扫描线 + 待处理闪烁”复合动画。
- `pendingActionCount > 0` 时提升帧率与亮度，强化“需要你立即操作”的感知。

**Step 2: 上岛过渡动画升级**
- 为 closed→open、open→closed 增加分层过渡（scale + opacity + slight blur/scan reveal），避免硬切。
- 保证与音乐/电量 Live Activity 的优先级规则不冲突。

**Step 3: 细节一致性与可读性**
- provider 标识、计数与动效颜色统一到同一状态机（running / waiting / done）。
- 在非 Retina 与低帧率场景下保底可读（限制像素块数量与刷新频率上限）。

**Step 4: 动效开关与回退策略（可选）**
- 增加“像素动画增强”开关与性能回退策略（低性能设备自动降级到简化动画）。
- 保持默认值与对标产品一致（开箱即有明显动效反馈）。

**Step 5: 验收门槛**
- 闭合态可稳定 10~16 FPS 视觉节奏，无抖动与闪烁噪点。
- pending 出现后 300ms 内进入高亮节奏；pending 清空后平滑回落。
- 不影响 notch 手势开合与 hover 逻辑。

---

## 里程碑建议

1. **M1（0.5 天）**：完成统计口径修复 + 活跃状态机阈值 + 编译通过。
2. **M2（1 天）**：完成高密度行视图 + 子代理自动高度 + 操作按钮行内化。
3. **M3（0.5 天）**：完成设置页信息架构与授权逻辑重排。
4. **M4（0.5 天）**：完成首启流程与空态，补齐 i18n，执行回归清单。

## 风险与应对

1. 终端/CLI 事件字段继续变化。
- 对策：保留宽容解析，但把“状态判定”收敛到有限字段，未知字段仅作补充。

2. 本地目录数据量大导致扫描慢。
- 对策：扫描仅冷启动和手动触发，实时刷新完全依赖 bridge 事件。

3. 授权目录引起沙盒阻塞。
- 对策：授权流程主线程仅做选择，不做重扫描；扫描在后台并带预算上限。
