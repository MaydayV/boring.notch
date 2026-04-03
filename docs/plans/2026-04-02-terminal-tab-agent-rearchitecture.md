# Terminal Tab Agent 功能改版文档（对标 VibeIsland）

## 1. 改版目标

将当前 `Agents`（终端 tab）从“目录扫描驱动”升级为“事件桥接驱动（event-first）”，实现和参考产品一致的核心体验：

1. 多 CLI 工具统一会话面板（Claude/Codex/Gemini/OpenCode/OpenClaw/Cursor/更多可扩展）。
2. 实时会话状态与用量更新（无需频繁重扫本地目录）。
3. 可交互动作闭环（Approve / Deny / Answer / Jump）。
4. 可安装/修复 hooks 的运维能力（避免“读不到数据”）。
5. 与终端/IDE 跳转配合，减少上下文切换。

## 2. 当前问题（重构动机）

1. 以扫描为主会带来主线程压力，tab 首次打开容易卡顿。
2. 目录权限依赖手工授权，用户未授权时容易空白。
3. 各 CLI 文件格式不稳定，兼容成本高。
4. 交互动作已具备 UI，但缺少稳定“请求-确认-回写”进程协同链路。
5. 中文/多语言虽已 key 化，但功能链路提示文案仍不完整。

## 3. 对标功能点（与参考产品保持一致）

### 3.1 会话面板能力

1. 按 provider 聚合会话，支持过滤：`All / Needs Action / Running / Done`。
2. 卡片展示：
   - Provider 名称与会话标题
   - 状态（running / waiting approval / waiting question / completed / failed）
   - 用量（tokens / turns / cost）
   - 最后活跃时间
3. 低成本摘要：今日会话数、运行数、待处理动作数、今日 tokens 与费用估算。

### 3.2 交互动作能力（确认按钮链路）

必须完整支持以下按钮/动作（MVP gate）：

1. `Approve`（允许）
2. `Deny`（拒绝）
3. `Answer`（文本回答）
4. `Choice`（多选/单选回答）
5. `Jump`（跳回终端/会话）

动作链路要求：

1. CLI 触发 `action.requested` 事件（包含 `requestId`、`sessionId`、`provider`）。
2. 用户点击按钮后 App 产生 `action.responded`（approved/denied/answered）。
3. Bridge 将响应回传 CLI（或通过约定响应文件被 bridge 消费）。
4. UI 收到 `action.resolved`/`action.responded` 后自动收敛待处理状态。

### 3.3 CLI hooks 运维能力

设置页提供 `CLI Hooks` 区块：

1. `Install` / `Repair` 一键安装修复。
2. 按 provider 显示状态：
   - `Installed`
   - `Not installed`
   - `CLI not found`
   - `Unsupported`
3. 显示 bridge command 路径，便于排查。
4. 支持幂等执行（重复安装不会破坏已有配置）。

## 4. 目标架构（event-first，scan-fallback）

### 4.1 进程与数据流

1. `CLI Hook`：各 CLI 在关键事件触发 bridge 命令。
2. `Bridge`：标准化输入，写入 `events.ndjson`，必要时等待响应并返回 `{"continue":true/false}`。
3. `App`：
   - `AgentBridgeClient` 监听事件文件变化（watcher）
   - `AgentHubManager` 执行轻量刷新（仅事件）
   - 周期性/手动触发文件扫描兜底（scan-fallback）
4. `Response`：App 将按钮动作写入 `responses.ndjson`，bridge 消费后反馈 CLI。

### 4.2 数据协议（统一 NDJSON）

事件建议最小字段：

1. `schemaVersion`
2. `provider`
3. `event`（session.started / usage.updated / action.requested / action.resolved / session.completed / session.failed / session.updated）
4. `sessionId`
5. `requestId`（动作类可选）
6. `timestamp`
7. `payload`（保留原始 CLI payload 与扩展字段）

响应建议：

1. `event = action.responded`
2. `provider/sessionId/requestId`
3. `outcome = approved | denied | answered`
4. `message`（回答文本）

### 4.3 刷新策略

1. 事件变更触发：`includeFilesystem = false`（轻量合并）。
2. 全量扫描触发：
   - 手动刷新按钮
   - 首次进入 tab
   - 间隔到期（如 30s）时后台扫描
3. 避免双刷新与抖动：
   - 防抖
   - 并发刷新互斥
   - 扫描结果缓存

## 5. 模块重构方案

### 5.1 `AgentModels.swift`

1. 扩展 provider（至少：`cursor/droid/qoder`）。
2. provider 统一定义：
   - `displayName`
   - `commandName`
   - `resumeCommand`
   - `scanRootPaths`
   - `allowedExtensions`
3. 增强 payload 兼容查找（source/provider/event/session/request 推断）。

### 5.2 `AgentBridgeClient.swift`

1. 增加事件 watcher：文件变化实时回调。
2. 解析兼容：
   - 支持 `source` 推断 provider
   - 支持 payload 嵌套对象
   - 支持弱结构事件（仅 source + payload）
3. 保持 `responses.ndjson` append 写入能力。

### 5.3 `AgentHubManager.swift`

1. 初始化启动 watcher。
2. `refresh(force:includeFilesystem:)` 双模式。
3. 扫描缓存与扫描间隔控制，防止 tab 卡顿。
4. 交互动作结果强制刷新（确保按钮后状态及时变化）。

### 5.4 Hooks 安装器（新增）

新增 `AgentHookInstaller`：

1. 安装 bridge 命令到 `~/.boring-notch/bin/boring-notch-agent-bridge`。
2. 安装/修复：
   - `~/.codex/hooks.json`
   - `~/.claude/settings.json`
   - `~/.gemini/settings.json`
3. 检测每个 provider hook 状态。
4. 脚本使用系统 `python3` 处理 stdin JSON，无第三方依赖。

### 5.5 `AgentsSettingsView.swift`

新增 `CLI Hooks` 区块：

1. Install/Repair 按钮
2. Provider 状态清单
3. Bridge 路径
4. 状态提示（成功/失败）

## 6. 交互细节（按钮级别）

### 6.1 权限请求卡片

按钮：

1. `Approve`
2. `Deny`
3. `Jump`

行为：

1. 点击后立即乐观更新按钮状态（可选）
2. 写入 `responses.ndjson`
3. 等待 bridge 回执事件更新为 resolved
4. 超时则标记 `may need attention`

### 6.2 问题卡片

按钮：

1. 选项按钮（如有 options）
2. 文本输入 + `Send`
3. `Jump`

行为：

1. 输入校验（空文本不提交）
2. 回写响应并刷状态

### 6.3 Jump 行为

1. 优先执行 `session.resumeCommand`
2. 失败时回落到 provider 命令模板
3. 将失败错误在 tab banner 中显示

## 7. 兼容策略

1. 新架构主路径：hooks 事件。
2. 老架构兜底：目录扫描。
3. 对未知 provider 事件：
   - 保留到会话列表（可展示）
   - 不暴露危险动作
4. payload 字段缺失时回退默认值，避免 UI 崩溃。

## 8. 验证标准（交付门槛）

### 8.1 功能验收

1. 安装 hooks 后，启动 CLI 会话可在 1-2 秒内出现在终端 tab。
2. 权限/问题动作可通过按钮提交并被 bridge 消费。
3. 用量字段出现时可展示；缺失时 UI 平稳降级。
4. `Jump` 可打开目标终端并执行 resume 命令。

### 8.2 性能与稳定性

1. 点击终端 tab 不得卡死。
2. 高频事件下 CPU 受控（去抖+增量刷新）。
3. 异常文件/坏 JSON 不致崩溃。

### 8.3 多语言

1. 新增文案必须走 `Localizable.xcstrings` key。
2. 不允许 `isChinese` 之类分支硬编码。

## 9. 分阶段实施

### 阶段 A（本次）

1. 文档定稿（本文件）
2. hooks 安装器 + 设置页
3. bridge watcher + event-first 刷新
4. provider 扩展与兼容
5. 编译与运行验证

### 阶段 B（下一轮）

1. socket bridge（替代纯文件桥接，进一步降延迟）
2. IDE 精确 tab 跳转增强（VSCode/Zed 插件协同）
3. 动作快捷键与批量审批

## 10. 风险与对策

1. 各 CLI hook payload 差异大  
对策：在 bridge 与 parser 双侧做“宽容解析 + 字段推断”。

2. hooks 被第三方覆盖  
对策：设置页 `Repair` + 定期状态检测提示。

3. 沙盒限制导致路径不可读  
对策：event-first 降低目录依赖，扫描仅兜底并给出授权提示。

4. 兼容历史逻辑引入复杂度  
对策：保持 `AgentHubManager` 为唯一合并入口，减少分叉。
